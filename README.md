# RentalPlatform – Decentralized P2P Asset Rental Smart Contract
A decentralized peer-to-peer rental platform built in Solidity, enabling users to securely rent physical assets using smart contracts, collateral (safety bonds), and dual-party confirmation mechanisms.
This project demonstrates real-world blockchain concepts such as escrow handling, time-based penalties, reputation systems, and trust minimization.

## Features
### Asset Management
Register physical assets for rent
Update rental pricing and descriptions
Enable / disable asset availability
Prevent double renting of the same asset

### Secure Rental Flow
Safety bond (collateral) locked in the contract
Automatic release of funds after rental completion
Protection against unpaid rentals or damage risk

### Dual Handshake Mechanism
Pickup confirmation by both owner & borrower
Return confirmation by both parties
Rental activates and completes only after mutual agreement

### Late Return Penalties
5% safety bond penalty per hour
Time-based enforcement using block timestamps
Penalty capped at safety bond amount

### Reputation System
Reputation increases for successful, on-time rentals
Reputation decreases for late returns
Tracks total completed rentals per user

### Smart Contract Design
Core Structs
PhysicalAsset – Asset details and pricing
RentalAgreement – Rental lifecycle and confirmations

## Rental Status Lifecycle
Pending → Active → Completed
             ↓
         Cancelled

## Technology Stack
- Solidity ^0.8.0
- Ethereum / EVM Compatible Chains
- Foundry / Hardhat compatible
- MetaMask supported
- Sepolia / Local test networks
