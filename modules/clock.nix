# Time handling on guest PCs. Whether a PC keeps its hardware clock in local time
# (Windows) or UTC (most Linux installs) cannot be detected, so assume local time, as
# most guest PCs run Windows; elsewhere the clock is off until NTP corrects it. The
# hardware clock is only ever read, never written, so the guest's own OS keeps a
# correct clock either way.
{
  time.timeZone = "Europe/Berlin";
  time.hardwareClockInLocalTime = true;

  # Unlike systemd-timesyncd, chrony without rtcsync keeps the kernel from copying the
  # system time to the hardware clock every 11 minutes.
  services.chrony = {
    enable = true;
    enableRTCTrimming = false;
  };

  # The RTC driver is a module. When it registers, the kernel sets the system clock
  # from the hardware clock as UTC, undoing the local-time offset systemd applied
  # earlier in boot, so read the hardware clock again as local time.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="rtc", KERNEL=="rtc0", TAG+="systemd", ENV{SYSTEMD_WANTS}+="lanos-rtc-localtime.service"
  '';
  # Reads sysfs instead of using hwclock, which waits for an RTC update interrupt that
  # not every machine (or VM) delivers.
  systemd.services.lanos-rtc-localtime = {
    description = "Read the hardware clock as local time";
    before = [
      "time-set.target"
      "chronyd.service"
    ];
    serviceConfig.Type = "oneshot";
    script = ''
      rtc=/sys/class/rtc/rtc0
      date --set="@$(date --date="$(cat $rtc/date) $(cat $rtc/time)" +%s)"
    '';
  };
}
