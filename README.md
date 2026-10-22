# owntone.nix

A NixOS module for [OwnTone](https://owntone.github.io/owntone-server/), an audio
server for local music libraries, AirPlay receivers, and supported Chromecast
receivers. OwnTone's native configuration is written as Nix attributes.

## Use with flakes

Add the input and import its module:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    owntone = {
      url = "github:jasonmc/owntone.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, owntone, ... }: {
    nixosConfigurations.music-server = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        owntone.nixosModules.default
        ./configuration.nix
      ];
    };
  };
}
```

Then configure the server in `configuration.nix`:

```nix
{
  services.owntone = {
    enable = true;
    openFirewall = true;
    config = {
      general.trusted_networks = [ "lan" ];
      library = {
        name = "Music";
        directories = [ "/srv/music" ];
      };
      audio.type = "disabled"; # Playback through network receivers only.
      airplay_shared = {
        control_port = 6001;
        timing_port = 6002;
      };
    };
  };

  # Change this interface to match your LAN.
  networking.firewall.interfaces.enp1s0.allowedUDPPorts = [ 319 320 6001 6002 ];

  # Useful when the music library lives on a separate filesystem.
  systemd.services.owntone.unitConfig.RequiresMountsFor = [ "/srv/music" ];
}
```

The music directory must exist and be readable by the `owntone` user. Avahi is
enabled for receiver discovery. Open the web interface at `http://<host>:3689/`.
For a non-flake setup, import this repository's `default.nix` as a NixOS module.

## Options and defaults

| Option | Default | Purpose |
| --- | --- | --- |
| `services.owntone.enable` | `false` | Enable the service. |
| `package` | `pkgs.owntone` | Choose the OwnTone package. |
| `config` | `{}` | Native OwnTone configuration as Nix attributes. |
| `dataDir` | `/var/lib/owntone` | Absolute path to the persistent state directory. |
| `user` / `group` | `owntone` | Service identity; custom identities must already be declared. |
| `port` | `3689` | Default library/HTTP port; `config.library.port` can override it. |
| `openFirewall` | `false` | Open the configured library and WebSocket TCP ports. |
| `extraArgs` | `[]` | Additional daemon arguments. |

Defaults provide database, backup, log, and cache paths under `dataDir`;
WebSocket port 3688; and `general.trusted_networks = [ "any" ]`. Override
`trusted_networks` to control which clients can connect without authentication,
as the example does for LAN clients. See the
[upstream configuration](https://owntone.github.io/owntone-server/configuration/)
for available settings and authentication behavior. Credentials in `config`
are written to the Nix store.

State under `/var/lib` is managed by systemd, including repairing ownership when
numeric service IDs change. Other state locations are created with tmpfiles.
The cache has its own writable directory. AirPlay 2 receives the
`CAP_NET_BIND_SERVICE` capability for PTP timing on UDP ports 319 and 320.
Additional UDP firewall rules are explicit, as shown above.

Configuration values can be strings, numbers, booleans, lists, and nested
attribute sets. `null` attributes are omitted. Device-specific sections can use
quoted attribute names, for example:

```nix
services.owntone.config."airplay \"Bedroom\"" = {
  max_volume = 8;
};
```

Settings merge recursively across imported modules, and lists are concatenated.
Use `lib.mkDefault` for defaults, `lib.mkForce` to replace a value or list, and
`lib.mkBefore` / `lib.mkAfter` to control list ordering. Conflicting scalar values
at the same priority cause an evaluation error.

## Checks

The flake pins NixOS 26.05 and checks configuration merging, state path
validation, rendering (including edge cases), and service startup in a NixOS VM.
On an x86_64 Linux machine with KVM, run:

```sh
nix flake check --print-build-logs
```

The VM test checks service startup, the HTTP API, the WebSocket listener,
database/cache creation, PTP port binding, and recovery of existing state with
old numeric ownership. It uses a temporary music filesystem, not real devices.
Physical speaker playback and synchronization require a real receiver.

OwnTone currently documents that Google Nest Hub playback is unsupported and
Chromecast cannot precisely synchronize with AirPlay. See the
[upstream Chromecast notes](https://owntone.github.io/owntone-server/audio-outputs/chromecast/).

## License

MIT. OwnTone itself is a separate project with its own license.
