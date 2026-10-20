# crashphysics

> **Work in progress (W.I.P).** Things will change and break.

Vehicle crash physics for FiveM (ESX, `ox_lib`, `heino_bridge`, `heino_interactions`).

- Impact detection with four severity levels
- Jammed doors and trapped players
- Crash effects, injuries, seatbelt
- Vehicle damage and deformation
- Debris and sweeping

## Install

1. Put `crashphysics` in your resources folder.
2. `ensure crashphysics` after its dependencies.

Settings are in `config.lua`. Admin commands: `/crashsim`, `/crashinfo`, `/crashclear`, `/crashdebris`.

## Contributing

Anyone is welcome to contribute. Open an issue or a pull request. Tests: `lua tests/server_test.lua` and `lua tests/client_test.lua`.

## License

AGPL-3.0
