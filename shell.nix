{ pkgs ? (import <nixpkgs> {}), ... }:
with pkgs;
let
  otp = beam.packages.erlang_28;
  basePackages = [
    otp.elixir_1_19
    otp.erlang
  ];

  # Hot reloading stuff
  inputs = basePackages ++ lib.optionals stdenv.isLinux [ inotify-tools ]
    ++ lib.optionals stdenv.isDarwin
    (with darwin.apple_sdk.frameworks; [ CoreFoundation CoreServices ]);
in
pkgs.mkShell {
  buildInputs = inputs;

  shellHook = ''
    # keep your shell history in iex
    export ERL_AFLAGS="-kernel shell_history enabled"

    # Force UTF8 in CLI
    export LANG="C.UTF-8"

    # Database env
    export POSTGRES_PASSWORD=postgres
    export POSTGRES_HOST=localhost
    export POSTGRES_USER=postgres
    export POSTGRES_PORT=5432

    # this isolates mix to work only in local directory
    mkdir -p .nix-mix .nix-hex
    export MIX_HOME=$PWD/.nix-mix
    export HEX_HOME=$PWD/.nix-hex

    # make hex from Nixpkgs available
    # `mix local.hex` will install hex into MIX_HOME and should take precedence
    export MIX_PATH="${otp.hex}/lib/erlang/lib/hex/ebin"
    export PATH=$MIX_HOME/bin:$HEX_HOME/bin:$PATH
  '';
}
