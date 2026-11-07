{
  services.bird = {
    enable = true;
    config = ''
      router id 10.10.1.95;

      protocol device {}
    '';
  };
}
