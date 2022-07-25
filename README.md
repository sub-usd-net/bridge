## Subnet Bridge and Fuji Bridge

These contracts work with a bridge-manager tool to complete the end-to-end bridging experience.
This bridge is experimental and not recommended for robust production deployments.

### Architecture

2 Networks (C-Chain and a Subnet), each with a bridge contract. The C-Chain bridge accepts user ERC-20 deposits
for a *specific* token (in our use-case, it will be pre-determined stablecoin such as USDC). Upon a deposit, an event is
emitted. The bridge manager then completes the transfer on the subnet side, where tokens are minted (or, if the bridge has
locked reserves, it uses those first). The process works similarly in the opposite direction with the caveat that on the subet
side, the native token is used and an ERC-20 stablecoin token is used on the C-Chain side.

#### Implementation

To keep it simple, each side of the bridge maintains a `depositId` that is incremented when a user makes a deposit.
Each side of the bridge also maintains a `crossChainDepositId` that is incremented (guaranteed to be sequential) when
the bridge completes the transfer. Hence `Chain1.depositId = Chain2.crossChainDepositId`. So just by looking at these
values, one can quicly and easily surmise the number of outstanding transfers.

### Testing

`forge test`

### Current Deployments

#### Fuji C-Chain

Bridge: 0xb241c0cd258cae6545f4a1ee847d06115c210445
FakeStablecoin: 0x438c3cea05705460b82b5be5a0178c6bdd84926c
BridgingHelper: 0x6a20d061f98f50e7fa9037b5d9ed49692bc500f6

#### Subnet

Bridge: 0x1b6ceba69e7b07443f12c35313da7e63c2acee18
