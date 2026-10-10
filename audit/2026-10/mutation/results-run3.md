# Mutation testing — src/PsyNFTV2.sol

**Score: 94.4%** — 168 of 178 valid mutants killed (0 did not compile and are excluded).

## Survivors

| # | Line | Kind | Mutation |
|---|---|---|---|
| 39 | 152 | modifier-removed | `drop nonReentrant: nonReentrant` |
| 51 | 168 | relational | `> -> >=: if (id + 1 > _migrationCeiling) {` |
| 73 | 221 | modifier-removed | `drop nonReentrant: function initialMint() external onlyCoreContract nonReentrant {` |
| 86 | 241 | modifier-removed | `drop nonReentrant: function batchMintInFibonacci() external onlyCoreContract nonReentrant {` |
| 102 | 281 | relational | `> -> >=: block.timestamp > approvedTransfers[_tokenId].transferExpiryDate,` |
| 114 | 312 | relational | `<= -> <: require(block.timestamp <= approvedTransfers[_tokenId].transferExpiryDate, "PsyNFT: Approv` |
| 148 | 389 | modifier-removed | `drop nonReentrant: function rescueERC20(address token, address to, uint256 amount) external onlyOwner nonReen` |
| 152 | 396 | modifier-removed | `drop nonReentrant: function rescueERC721(address token, address to, uint256 tokenId_) external onlyOwner nonR` |
| 157 | 404 | modifier-removed | `drop nonReentrant: function rescueETH(address payable to, uint256 amount) external onlyOwner nonReentrant {` |
| 165 | 434 | logical | `&& -> //: if (from != address(0) && approvedTransfers[tokenId_].transferExpiryDate != 0) {` |

## By kind

| Kind | Valid | Killed |
|---|---|---|
| arith | 12 | 12 |
| bool | 9 | 9 |
| constant | 8 | 8 |
| logical | 5 | 4 |
| modifier-removed | 24 | 18 |
| negation | 5 | 5 |
| relational | 44 | 41 |
| require-removed | 31 | 31 |
| stmt-deleted | 40 | 40 |
