{ config, lib, pkgs, ... }:
let
  inherit (lib)
    mkDefault
    mkEnableOption
    mkIf
    mkOption
    mkPackageOption
    recursiveUpdate
    types;
  owntoneLib = import ./owntone-lib.nix { inherit lib; };
  cfg = config.services.owntone;
  managedStateDir = lib.hasPrefix "/var/lib/" cfg.dataDir;
  configValue = types.nullOr (types.oneOf [
    types.bool
    types.int
    types.float
    types.str
    types.path
    (types.listOf configValue)
    (types.attrsOf configValue)
  ]) // {
    description = "OwnTone configuration value";
  };

  baseConfig = {
    general = {
      uid = cfg.user;
      db_path = "${cfg.dataDir}/database.db";
      db_backup_path = "${cfg.dataDir}/database.bak";
      cache_dir = "${cfg.dataDir}/cache";
      loglevel = "log";
      logfile = "${cfg.dataDir}/owntone.log";
      trusted_networks = [ "any" ];
      websocket_port = 3688;
    };
    library.port = cfg.port;
  };

  effectiveConfig = recursiveUpdate baseConfig cfg.config;
  configFile = pkgs.writeText "owntone.conf" (owntoneLib.renderConfig effectiveConfig);
  execArgs = [ "-f" "-c" (toString configFile) ] ++ cfg.extraArgs;
in {
  options.services.owntone = {
    enable = mkEnableOption "the Owntone media server";

    package = mkPackageOption pkgs "owntone" { };

    user = mkOption {
      type = types.str;
      default = "owntone";
      description = "User the Owntone daemon runs as.";
    };

    group = mkOption {
      type = types.str;
      default = "owntone";
      description = "Group the Owntone daemon runs as.";
    };

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/owntone";
      description = "Absolute path to the directory Owntone uses for its state and cache.";
    };

    config = mkOption {
      type = types.attrsOf configValue;
      default = { };
      description = ''
        Owntone configuration expressed as a Nix attribute set. Rendered to `owntone.conf`
        together with a small set of defaults (paths, logging, trusted networks). Values
        can be strings, paths, integers, booleans, lists, or nested attribute sets to
        represent sub-blocks. Attribute sets merge recursively across modules and
        lists are concatenated. Normal module priorities apply to individual values.
      '';
    };

    extraArgs = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Extra arguments passed to `owntone`.";
    };

    port = mkOption {
      type = types.port;
      default = 3689;
      description = "Default library port. Can be overridden by services.owntone.config.library.port.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to open the library and WebSocket TCP ports.";
    };
  };

  config = mkIf cfg.enable {
    services.avahi.enable = mkDefault true;

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall
      (builtins.filter (port: port != 0) [
        effectiveConfig.library.port
        effectiveConfig.general.websocket_port
      ]);

    users.users = mkIf (cfg.user == "owntone") {
      owntone = {
        isSystemUser = true;
        home = cfg.dataDir;
        group = cfg.group;
        description = "Owntone media server service user";
      };
    };

    users.groups = mkIf (cfg.group == "owntone") { owntone = { }; };

    systemd.tmpfiles.rules = lib.optional (!managedStateDir)
      "d '${cfg.dataDir}' 0750 ${cfg.user} ${cfg.group} -" ++ [
      "d '${effectiveConfig.general.cache_dir}' 0750 ${cfg.user} ${cfg.group} -"
    ];

    systemd.services.owntone = {
      description = "Owntone media server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "avahi-daemon.service" ];
      wants = [ "avahi-daemon.service" ];

      serviceConfig = {
        ExecStart = "${cfg.package}/bin/owntone ${lib.escapeShellArgs execArgs}";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.dataDir;
        # Also repairs ownership if the service user's numeric UID has changed.
        StateDirectory = lib.optional managedStateDir (lib.removePrefix "/var/lib/" cfg.dataDir);
        StateDirectoryMode = "0750";
        # AirPlay 2's PTP clock binds UDP ports 319 and 320.
        AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
        CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];
        Restart = "on-failure";
      };
    };
  };
}
