// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IVerifySig {
    function isValidSig(address _signer, bytes32 _hash, bytes memory _signature) external returns (bool);
}
