# Sparrow Finance - Starknet Contracts

Liquid staking protocol for Starknet (spSTRK and spWBTC).

## Overview

Liquid staking contracts enabling users to stake STRK and WBTC on Starknet, receiving liquid tokens that appreciate in value as rewards accrue.

**Deployed Contracts:**
- **spSTRK** (Sepolia Testnet): `0x0239a1483EaC0B6A765231DF38c853bcd40Bd57fe44B047Dc537943B3fC693e6`
- **spWBTC**: In development

**Explorer:** https://sepolia.voyager.online/contract/0x0239a1483EaC0B6A765231DF38c853bcd40Bd57fe44B047Dc537943B3fC693e6

## Technology Stack

- **Language:** Cairo v2.12.2
- **Framework:** Scarb v2.12.2
- **Testing:** Starknet Foundry v0.50.0
- **Components:** OpenZeppelin Cairo (ERC20, Ownable, Upgradeable, Pausable, ReentrancyGuard)

## Key Features

- Liquid staking: STRK → spSTRK
- Exchange rate appreciation model
- Unlock + claim window system (7-day unlock, 7-day claim)
- 8% protocol fee (5% DAO, 3% Dev)
- Governance controls
- Emergency pause mechanism

## Installation

```bash
# Install Cairo and Scarb
curl --proto '=https' --tlsv1.2 -sSf https://docs.swmansion.com/scarb/install.sh | sh

# Build contracts
scarb build

# Run tests
scarb test
```

## Contract Structure

```
src/
├── sp_strk.cairo          # Main spSTRK contract
├── interfaces/
│   └── sp_strk.cairo      # Contract interface
└── lib.cairo              # Module exports
```

## Security

- OpenZeppelin Cairo components
- Reentrancy protection
- Access control (Ownable)
- Pausable for emergencies
- Comprehensive test coverage

## License

MIT License

## Links

- Website: https://sparrowfinance.xyz
- Docs: https://docs.sparrowfinance.xyz
- Twitter: https://x.com/SPROFinance
- GitHub: https://github.com/Sparrow-Finance
