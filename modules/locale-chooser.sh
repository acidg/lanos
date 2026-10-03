# Asks the player for language and keyboard layout, stores both in their Plasma config
# and restarts the session, because the language only applies to programs started
# afterwards. With --first-login it runs only once per stick.

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
done_marker="$config_dir/lanos/locale-chosen"

first_login=false
if [[ "${1:-}" == "--first-login" ]]; then
  first_login=true
fi
if [[ "$first_login" == true && -e "$done_marker" ]]; then
  exit 0
fi

mkdir -p "$(dirname "$done_marker")"
touch "$done_marker"

old_lang=$(kreadconfig6 --file plasma-localerc --group Formats --key LANG --default "${LANG:-}")
old_layouts=$(kreadconfig6 --file kxkbrc --group Layout --key LayoutList --default "$DEFAULT_LAYOUTS")

preselect() {
  if [[ "$1" == "$2" ]]; then
    echo on
  else
    echo off
  fi
}

current_lang=en
if [[ "$old_lang" == de_* ]]; then
  current_lang=de
fi
if ! lang=$(kdialog --title "LANOS" --radiolist "Sprache / Language" \
  de "Deutsch" "$(preselect de "$current_lang")" \
  en "English" "$(preselect en "$current_lang")"); then
  exit 0
fi

if ! layout=$(kdialog --title "LANOS" \
  --radiolist "Tastatur / Keyboard (Alt+Shift wechselt / switches)" \
  de "Deutsch (QWERTZ)" "$(preselect de "${old_layouts%%,*}")" \
  us "English US (QWERTY)" "$(preselect us "${old_layouts%%,*}")"); then
  exit 0
fi

case "$lang" in
  de)
    new_lang=de_DE.UTF-8
    language=de
    ;;
  *)
    new_lang=en_US.UTF-8
    language=en_US
    ;;
esac
case "$layout" in
  de) new_layouts=de,us ;;
  *) new_layouts=us,de ;;
esac

if [[ "$new_lang" == "$old_lang" && "$new_layouts" == "$old_layouts" ]]; then
  exit 0
fi

kwriteconfig6 --file plasma-localerc --group Formats --key LANG "$new_lang"
kwriteconfig6 --file plasma-localerc --group Translations --key LANGUAGE "$language"
kwriteconfig6 --file kxkbrc --group Layout --key Use --type bool true
kwriteconfig6 --file kxkbrc --group Layout --key LayoutList "$new_layouts"
kwriteconfig6 --file kxkbrc --group Layout --key Options "$XKB_OPTIONS"
kwriteconfig6 --file kxkbrc --group Layout --key ResetOldOptions --type bool true

if [[ "$first_login" == false ]]; then
  if ! kdialog --title "LANOS" --warningcontinuecancel \
    "Die Sitzung wird neu gestartet. / The session restarts now."; then
    exit 0
  fi
fi
qdbus org.kde.Shutdown /Shutdown org.kde.Shutdown.logout
