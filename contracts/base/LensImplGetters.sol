// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

import {ILensImplGetters} from 'contracts/interfaces/ILensImplGetters.sol';

contract LensImplGetters is ILensImplGetters {
    address internal immutable FOLLOW_NFT_IMPL;

    constructor(address followNFTImpl) {
        FOLLOW_NFT_IMPL = followNFTImpl;
    }

    /// @inheritdoc ILensImplGetters
    function getFollowNFTImpl() external view override returns (address) {
        return FOLLOW_NFT_IMPL;
    }
}
