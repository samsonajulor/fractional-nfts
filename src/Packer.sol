// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract PackedValues {
    uint256 private packedValues;

    function setPackedValues(uint128 value1, uint128 value2) public {
        packedValues = (uint256(value1) << 128) | uint256(value2);
    }

    function getPackedValues() public view returns (uint128 value1, uint128 value2) {
        assembly {
            let packed := sload(packedValues.slot)
            value1 := shr(128, packed)
            value2 := and(packed, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
        }
    }
}
