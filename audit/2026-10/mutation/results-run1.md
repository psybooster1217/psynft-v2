# Mutation testing — src/PsyNFTV2.sol

**Score: 86.5%** — 154 of 178 valid mutants killed (0 did not compile and are excluded).

## Survivors

| # | Line | Kind | Mutation |
|---|---|---|---|
| 39 | 152 | modifier-removed | `drop nonReentrant: nonReentrant` |
| 51 | 168 | relational | `> -> >=: if (id + 1 > _migrationCeiling) {` |
| 54 | 168 | arith | `+1 -> +0: if (id + 1 > _migrationCeiling) {` |
| 59 | 197 | modifier-removed | `drop onlyOwner: ) external onlyOwner notFinalized {` |
| 66 | 205 | stmt-deleted | `delete: controlledTransfers = controlledTransfers_;` |
| 73 | 221 | modifier-removed | `drop nonReentrant: function initialMint() external onlyCoreContract nonReentrant {` |
| 86 | 241 | modifier-removed | `drop nonReentrant: function batchMintInFibonacci() external onlyCoreContract nonReentrant {` |
| 100 | 279 | relational | `< -> <=: require(_tokenId < tokenId, "PsyNFT: Non Existent Token");` |
| 106 | 288 | stmt-deleted | `delete: emit TransferApproved(_tokenId, _to, expiry);` |
| 126 | 343 | stmt-deleted | `delete: emit TreasuryUpdated(treasury, _treasury);` |
| 131 | 351 | bool | `false -> true: emit ControlledTransfersSet(false);` |
| 132 | 351 | stmt-deleted | `delete: emit ControlledTransfersSet(false);` |
| 133 | 355 | modifier-removed | `drop onlyOwner: function enableControlledTransfers() external onlyOwner {` |
| 137 | 358 | bool | `true -> false: emit ControlledTransfersSet(true);` |
| 138 | 358 | stmt-deleted | `delete: emit ControlledTransfersSet(true);` |
| 144 | 370 | stmt-deleted | `delete: emit BaseUriUpdated(_uri);` |
| 148 | 389 | modifier-removed | `drop nonReentrant: function rescueERC20(address token, address to, uint256 amount) external onlyOwner nonReen` |
| 150 | 392 | stmt-deleted | `delete: emit ERC20Rescued(token, to, amount);` |
| 151 | 396 | modifier-removed | `drop onlyOwner: function rescueERC721(address token, address to, uint256 tokenId_) external onlyOwner nonR` |
| 152 | 396 | modifier-removed | `drop nonReentrant: function rescueERC721(address token, address to, uint256 tokenId_) external onlyOwner nonR` |
| 155 | 400 | stmt-deleted | `delete: emit ERC721Rescued(token, to, tokenId_);` |
| 157 | 404 | modifier-removed | `drop nonReentrant: function rescueETH(address payable to, uint256 amount) external onlyOwner nonReentrant {` |
| 159 | 408 | stmt-deleted | `delete: emit ETHRescued(to, amount);` |
| 165 | 434 | logical | `&& -> //: if (from != address(0) && approvedTransfers[tokenId_].transferExpiryDate != 0) {` |

## By kind

| Kind | Valid | Killed |
|---|---|---|
| arith | 12 | 11 |
| bool | 9 | 7 |
| constant | 8 | 8 |
| logical | 5 | 4 |
| modifier-removed | 24 | 15 |
| negation | 5 | 5 |
| relational | 44 | 42 |
| require-removed | 31 | 31 |
| stmt-deleted | 40 | 31 |
