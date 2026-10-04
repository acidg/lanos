# The library server as a Docker image, for a host that holds a library store but does
# not run the master module: harmonia serves the store as a binary cache and nginx adds
# the index in front, as on a master. The library is mounted at /library.
{
  lib,
  dockerTools,
  writeShellScript,
  writeText,
  harmonia,
  nginx,
}:
let
  harmoniaAddress = "127.0.0.1:5001";

  harmoniaConfig = writeText "harmonia.toml" ''
    bind = "${harmoniaAddress}"
    real_nix_store = "/library/nix/store"
    nix_db_path = "/library/nix/var/nix/db/db.sqlite"
  '';

  # The container runs as the library's owner, not as root, so everything nginx writes
  # goes to /tmp.
  nginxConfig = writeText "nginx.conf" ''
    daemon off;
    error_log stderr;
    pid /tmp/nginx.pid;
    events {}
    http {
      access_log off;
      client_body_temp_path /tmp/body;
      proxy_temp_path /tmp/proxy;
      fastcgi_temp_path /tmp/fastcgi;
      uwsgi_temp_path /tmp/uwsgi;
      scgi_temp_path /tmp/scgi;
      types { application/json json; }
      server {
        listen 8080;
        # A new publish must reach the sticks right away.
        location = /games.json {
          root /library/index;
          add_header Cache-Control "no-cache";
        }
        # Game files are large; stream them instead of buffering them on disk.
        location / {
          proxy_pass http://${harmoniaAddress};
          proxy_buffering off;
          proxy_read_timeout 1h;
        }
      }
    }
  '';

  # Stops the container when either server stops, so Docker restarts it.
  start = writeShellScript "lanos-library" ''
    trap 'kill 0' TERM INT
    CONFIG_FILE=${harmoniaConfig} ${harmonia}/bin/harmonia-cache &
    ${nginx}/bin/nginx -e stderr -c ${nginxConfig} &
    wait -n
    exit 1
  '';
in
dockerTools.buildLayeredImage {
  name = "lanos-library";
  tag = "latest";
  contents = [ dockerTools.fakeNss ];
  extraCommands = ''
    mkdir -m 1777 tmp
  '';
  config = {
    Cmd = [ start ];
    Env = [ "HOME=/tmp" ];
    ExposedPorts."8080/tcp" = { };
  };
  meta.license = lib.licenses.mit;
}
