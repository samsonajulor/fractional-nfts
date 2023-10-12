## Smart Contract Overview

The `Marketplace` smart contract has several functions, data structures, errors, and events. Before you start using it, it's important to grasp its key components:

- `Listing` struct: Represents a listing with attributes such as the token address, token ID, price, signature, deadline, lister's address, and activity status.

- `listings` mapping: Stores all listings with a unique identifier (listing ID) as the key.

- `admin` address: Represents the administrator of the contract, set during deployment.

- `listingId` variable: Keeps track of the total number of listings created.

- Error messages: These are custom error messages that can be thrown in case of specific conditions not being met during contract execution.

- Events: The contract emits events when listings are created, executed, or edited.

## Key Functions

### 1. `createListing`

This function allows users to create a new listing for an ERC721 token.

Parameters:
- `Listing calldata l`: A `Listing` struct that contains information about the listing.

Actions and Checks:
- Checks if the sender is the owner of the ERC721 token.
- Verifies if the sender has approved the contract to manage the token.
- Ensures that the price is not less than 0.01 ether.
- Checks if the listing's deadline is in the future and at least 60 minutes away.
- Validates the provided signature.
- Appends the new listing to the storage.
- Emits a `ListingCreated` event.

### 2. `executeListing`

This function allows users to execute a listing by purchasing the ERC721 token.

Parameters:
- `uint256 _listingId`: The ID of the listing to execute.
- Sends ETH to the contract to match the listing's price.

Actions and Checks:
- Checks if the specified listing exists.
- Verifies that the listing has not expired.
- Ensures that the listing is active.
- Checks if the sent ETH matches the listing price.
- Transfers the ERC721 token to the buyer and the price to the seller.
- Emits a `ListingExecuted` event.

### 3. `editListing`

This function allows the lister of a listing to edit its price and activity status.

Parameters:
- `uint256 _listingId`: The ID of the listing to edit.
- `uint256 _newPrice`: The new price for the listing.
- `bool _active`: The new activity status for the listing.

Actions and Checks:
- Checks if the specified listing exists.
- Ensures that the sender is the lister of the listing.
- Updates the listing's price and activity status.
- Emits a `ListingEdited` event.

### 4. `getListing`

This function allows users to retrieve information about a specific listing by its ID.

Parameters:
- `uint256 _listingId`: The ID of the listing to retrieve.

Actions and Checks:
- Retrieves the information of the listing based on its ID.

## Usage Guide

### For Developers

1. **Deployment**: Deploy the `Marketplace` contract to the Ethereum network. Ensure that you specify the contract's administrator during deployment.

2. **Interacting with the Contract**: Developers can interact with the contract by calling its functions programmatically. This can be done using libraries like Web3.js or ethers.js in JavaScript or using the appropriate libraries in your preferred programming language.

3. **Error Handling**: Developers should handle errors gracefully when interacting with the contract. These errors are defined in the contract as custom error types.

