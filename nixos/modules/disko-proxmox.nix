{ lib, ... }:

{
  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_scsi"
    "virtio_net"
    "virtio_blk"
    "virtio_console"
    "sd_mod"
    "sr_mod"
    "ahci"
    "xhci_pci"
  ];

  boot.kernelParams = [
    "console=ttyS0,115200n8"
    "console=tty0"
  ];

  boot.loader.grub = {
    enable = true;
    devices = lib.mkForce [];
    extraConfig = ''
      serial --unit=0 --speed=115200
      terminal_input serial console
      terminal_output serial console
    '';
    mirroredBoots = lib.mkForce [{
      path = "/boot";
      devices = [ "/dev/sda" ];
      efiSysMountPoint = null;
      efiBootloaderId = null;
    }];
  };

  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/sda";
    content = {
      type = "gpt";
      partitions = {
        bios = {
          size = "1M";
          type = "EF02";
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
