# Generic hardware support: the stick boots on unknown guest PCs, so there is no
# per-machine hardware scan. Broad initrd module set (USB, NVMe, SATA, NICs) plus all
# firmware and CPU microcode.
{
  hardware.enableAllHardware = true;
  hardware.enableAllFirmware = true;
}
