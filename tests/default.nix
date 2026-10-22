{ pkgs }:
let
  lib = pkgs.lib;
  renderer = (import ../modules/owntone-lib.nix { inherit lib; }).renderConfig;
in {
  dataDirValidation =
    let
      evaluate = value: (pkgs.nixos [
        ../modules/owntone.nix
        { services.owntone.dataDir = value; }
      ]).config.services.owntone.dataDir;
      valid = [ "/var/lib/owntone" "/srv/owntone" ];
      invalid = [ "" "relative" "./state" "../state" ];
    in
    assert lib.assertMsg (map evaluate valid == valid)
      "Absolute OwnTone state paths must be accepted.";
    assert lib.assertMsg (lib.all (value: !(builtins.tryEval (evaluate value)).success) invalid)
      "Empty and relative OwnTone state paths must fail evaluation.";
    pkgs.runCommand "owntone-data-dir-validation" { } "touch $out";

  renderEdgeCases =
    let
      failures = lib.runTests {
        testEscaping = {
          expr = renderer {
            library.name = "Quote: \" Backslash: \\ Newline: \n Tab: \t";
          };
          expected = lib.strings.trim ''
            library {
              name = "Quote: \" Backslash: \\ Newline: \n Tab: \t"
            }
          '';
        };
        testNullAttributes = {
          expr = renderer {
            general = {
              admin_password = null;
              loglevel = "info";
            };
            mpd = null;
          };
          expected = lib.strings.trim ''
            general {
              loglevel = "info"
            }
          '';
        };
        testEmptyList = {
          expr = renderer { library.directories = [ ]; };
          expected = lib.strings.trim ''
            library {
              directories = {  }
            }
          '';
        };
        testNamedAirplaySection = {
          expr = renderer { "airplay \"Bedroom\"".max_volume = 8; };
          expected = lib.strings.trim ''
            airplay "Bedroom" {
              max_volume = 8
            }
          '';
        };
      };
    in
    assert lib.assertMsg (failures == [ ])
      "OwnTone renderer edge cases failed: ${builtins.toJSON failures}";
    pkgs.runCommand "owntone-render-edge-cases" { } "touch $out";

  configMerging =
    let
      evaluate = modules: (pkgs.nixos ([ ../modules/owntone.nix ] ++ modules))
        .config.services.owntone.config;
      merged = evaluate [
        {
          services.owntone.config = {
            library = {
              name = lib.mkDefault "Default library";
              directories = lib.mkBefore [ "/srv/music" ];
              compilation_artist = "Various Artists";
            };
            general.trusted_networks = lib.mkDefault [ "any" ];
          };
        }
        {
          services.owntone.config = {
            library = {
              name = "Shared library";
              directories = [ "/srv/other-music" ];
              port = 3690;
            };
            general.trusted_networks = lib.mkForce [ "lan" ];
          };
        }
      ];
      conflicting = builtins.tryEval ((evaluate [
        { services.owntone.config.library.name = "First"; }
        { services.owntone.config.library.name = "Second"; }
      ]).library.name);
    in
    assert lib.assertMsg (merged == {
      library = {
        name = "Shared library";
        directories = [ "/srv/music" "/srv/other-music" ];
        compilation_artist = "Various Artists";
        port = 3690;
      };
      general.trusted_networks = [ "lan" ];
    }) "OwnTone settings must merge recursively and respect module priorities.";
    assert lib.assertMsg (!conflicting.success)
      "Conflicting OwnTone scalar settings must fail evaluation.";
    pkgs.runCommand "owntone-config-merging" { } "touch $out";

  owntoneStartup = pkgs.testers.runNixOSTest {
    name = "owntone-startup";
    nodes.machine = { ... }: {
      imports = [ ../modules/owntone.nix ];
      services.owntone = {
        enable = true;
        openFirewall = true;
        config = {
          library.directories = [ "/srv/music" ];
          audio.type = "disabled";
          airplay_shared = {
            control_port = 6001;
            timing_port = 6002;
          };
        };
      };
      systemd.services.owntone.unitConfig.RequiresMountsFor = [ "/srv/music" ];
      fileSystems."/srv/music" = {
        device = "tmpfs";
        fsType = "tmpfs";
      };
      environment.systemPackages = [ pkgs.curl ];
    };
    testScript = ''
      machine.wait_for_unit("owntone.service")
      machine.wait_for_open_port(3689)
      machine.wait_for_open_port(3688)
      machine.succeed("curl --fail --silent http://localhost:3689/api/config")
      machine.wait_until_succeeds("test -s /var/lib/owntone/cache/daap.db")
      machine.succeed("test -s /var/lib/owntone/database.db")
      machine.succeed("ss -lun | grep ':319 '")
      machine.fail("grep -E 'Cache create failed|Error initializing Pulseaudio' /var/lib/owntone/owntone.log")

      # Recreate the old installation's numeric ownership before restarting.
      machine.systemctl("stop owntone.service")
      machine.succeed("chown -R 12345:12345 /var/lib/owntone")
      machine.systemctl("start owntone.service")
      machine.wait_for_open_port(3689)
      machine.succeed("curl --fail --silent http://localhost:3689/api/config")
      machine.succeed("test $(stat -c %U /var/lib/owntone/database.db) = owntone")
    '';
  };

  renderAttrset =
    let
      expected = ''
audio {
  adjust_period_seconds = 120
  card = "default"
  mixer = "PCM"
  mixer_device = "hw:0"
  nickname = "Computer"
  offset_ms = 5
  server = "localhost"
  sync_disable = true
  type = "alsa"
}

general {
  admin_password = "secret"
  bind_address = "::"
  cache_daap_threshold = 500
  cache_dir = "/var/lib/owntone/cache"
  db_backup_path = "/var/lib/owntone/database.bak"
  db_path = "/var/lib/owntone/database.db"
  high_resolution_clock = true
  ipv6 = false
  logfile = "/var/lib/owntone/owntone.log"
  loglevel = "info"
  speaker_autoselect = true
  trusted_networks = { "lan", "10.0.0.0/8" }
  uid = "owntone"
  websocket_interface = "eth0"
  websocket_port = 3688
}

library {
  allow_modifying_stored_playlists = true
  artwork_basenames = { "artwork", "cover", "Folder" }
  artwork_individual = true
  audiobooks = { "/Audiobooks" }
  clear_queue_on_stop_disable = true
  compilation_artist = "Various Artists"
  compilations = { "/Compilations" }
  decode_audio_filters = { "volume=replaygain=track" }
  default_playlist_directory = "/srv/music/Playlists"
  directories = { "/srv/music" }
  filepath_ignore = { "skipme" }
  filescan_disable = false
  filetypes_ignore = { ".db", ".ini" }
  follow_symlinks = true
  force_decode = { "ogg" }
  hide_singles = true
  itunes_overrides = true
  itunes_smartpl = true
  m3u_overrides = true
  max_rating = 100
  name = "My Music on %h"
  name_audiobooks = "Audiobooks"
  name_library = "Library"
  name_movies = "Movies"
  name_music = "Music"
  name_podcasts = "Podcasts"
  name_radio = "Radio"
  name_tvshows = "TV Shows"
  no_decode = { "flac" }
  only_first_genre = true
  password = "librarypass"
  pipe_autostart = true
  podcasts = { "/Podcasts" }
  port = 3689
  prefer_format = "alac"
  radio_playlists = true
  rating_updates = true
  read_rating = true
  write_rating = true
}

mpd {
  enable_httpd_plugin = true
  http_port = 8081
  port = 6600
}

spotify {
  album_override = true
  artist_override = true
  base_playlist_disable = true
  bitrate = 3
}

sqlite {
  pragma_cache_size_cache = 1000
  pragma_cache_size_library = 2000
  pragma_journal_mode = "WAL"
  pragma_mmap_size_cache = 0
  pragma_mmap_size_library = 0
  pragma_synchronous = 1
  vacuum = true
}

streaming {
  bit_rate = 192
  sample_rate = 44100
}
'';
      rendered = renderer {
        general = {
          admin_password = "secret";
          bind_address = "::";
          cache_daap_threshold = 500;
          cache_dir = "/var/lib/owntone/cache";
          db_backup_path = "/var/lib/owntone/database.bak";
          db_path = "/var/lib/owntone/database.db";
          high_resolution_clock = true;
          ipv6 = false;
          logfile = "/var/lib/owntone/owntone.log";
          loglevel = "info";
          speaker_autoselect = true;
          trusted_networks = [ "lan" "10.0.0.0/8" ];
          uid = "owntone";
          websocket_interface = "eth0";
          websocket_port = 3688;
        };
        library = {
          allow_modifying_stored_playlists = true;
          artwork_basenames = [ "artwork" "cover" "Folder" ];
          artwork_individual = true;
          audiobooks = [ "/Audiobooks" ];
          clear_queue_on_stop_disable = true;
          compilation_artist = "Various Artists";
          compilations = [ "/Compilations" ];
          decode_audio_filters = [ "volume=replaygain=track" ];
          default_playlist_directory = "/srv/music/Playlists";
          directories = [ "/srv/music" ];
          filepath_ignore = [ "skipme" ];
          filetypes_ignore = [ ".db" ".ini" ];
          filescan_disable = false;
          follow_symlinks = true;
          force_decode = [ "ogg" ];
          hide_singles = true;
          itunes_overrides = true;
          itunes_smartpl = true;
          m3u_overrides = true;
          max_rating = 100;
          name = "My Music on %h";
          name_audiobooks = "Audiobooks";
          name_library = "Library";
          name_movies = "Movies";
          name_music = "Music";
          name_podcasts = "Podcasts";
          name_radio = "Radio";
          name_tvshows = "TV Shows";
          no_decode = [ "flac" ];
          only_first_genre = true;
          password = "librarypass";
          pipe_autostart = true;
          podcasts = [ "/Podcasts" ];
          port = 3689;
          prefer_format = "alac";
          radio_playlists = true;
          rating_updates = true;
          read_rating = true;
          write_rating = true;
        };
        audio = {
          adjust_period_seconds = 120;
          card = "default";
          mixer = "PCM";
          mixer_device = "hw:0";
          nickname = "Computer";
          offset_ms = 5;
          server = "localhost";
          sync_disable = true;
          type = "alsa";
        };
        spotify = {
          album_override = true;
          artist_override = true;
          base_playlist_disable = true;
          bitrate = 3;
        };
        mpd = {
          enable_httpd_plugin = true;
          http_port = 8081;
          port = 6600;
        };
      sqlite = {
        pragma_cache_size_cache = 1000;
        pragma_cache_size_library = 2000;
        pragma_journal_mode = "WAL";
          pragma_mmap_size_cache = 0;
          pragma_mmap_size_library = 0;
          pragma_synchronous = 1;
          vacuum = true;
        };
      streaming = {
        bit_rate = 192;
        sample_rate = 44100;
      };
    };
      expectedTrimmed = lib.strings.trim expected;
    in assert expectedTrimmed == rendered;
      pkgs.runCommand "owntone-render-attrset" { } "echo ok > $out";
}
