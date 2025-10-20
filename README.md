## Liquid Staking Contract

Liquid staking contract to stake STRK token and receive liquid spSTRK token.
The contract uses [Scarb](https://docs.swmansion.com/scarb/docs) for development and testing purposes, and [Starknet Foundry](https://foundry-rs.github.io/starknet-foundry/index.html) as a toolchain to test.

### Prepare Environment

Simply install [Cairo and scarb](https://docs.swmansion.com/scarb/download).

### Dependencies

- scarb v2.12.2
- cairo v2.12.2
- sierra v1.7.0
- snforge v0.50.0
- starknet-foundry v0.50.0

### Build Contracts

```bash
scarb build
```

### Test Contracts

```bash
scarb test
```
