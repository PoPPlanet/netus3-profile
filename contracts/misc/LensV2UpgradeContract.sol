// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {ProxyAdmin} from 'contracts/misc/access/ProxyAdmin.sol';
import {Governance} from 'contracts/misc/access/Governance.sol';
import {ImmutableOwnable} from 'contracts/misc/ImmutableOwnable.sol';

contract LensV2UpgradeContract is ImmutableOwnable {
    ProxyAdmin public immutable PROXY_ADMIN;
    Governance public immutable GOVERNANCE;
    address public immutable newImplementation;
    address[] public newFollowModulesToWhitelist;
    address[] public newReferenceModulesToWhitelist;
    address[] public newActionModulesToWhitelist;

    constructor(
        address proxyAdminAddress,
        address governanceAddress,
        address owner,
        address lensHub,
        address newImplementationAddress,
        address[] memory newFollowModulesToWhitelist_,
        address[] memory newReferenceModulesToWhitelist_,
        address[] memory newActionModulesToWhitelist_
    ) ImmutableOwnable(owner, lensHub) {
        PROXY_ADMIN = ProxyAdmin(proxyAdminAddress);
        GOVERNANCE = Governance(governanceAddress);
        newImplementation = newImplementationAddress;
        newFollowModulesToWhitelist = newFollowModulesToWhitelist_;
        newReferenceModulesToWhitelist = newReferenceModulesToWhitelist_;
        newActionModulesToWhitelist = newActionModulesToWhitelist_;
    }

    function executeLensV2Upgrade() external onlyOwner {
        // _preUpgradeChecks();
        _upgrade();
        // _postUpgradeChecks();
    }

    function _upgrade() internal {
        PROXY_ADMIN.proxy_upgrade(newImplementation);

        _whitelistNewFollowModules();
        _whitelistNewReferenceModules();
        _whitelistNewActionModules();

        GOVERNANCE.clearControllerContract();
    }

    function _whitelistNewFollowModules() internal {
        uint256 newFollowModulesToWhitelistLength = newFollowModulesToWhitelist.length;
        uint256 i;
        while (i < newFollowModulesToWhitelistLength) {
            GOVERNANCE.lensHub_whitelistFollowModule(newFollowModulesToWhitelist[i], true);
            unchecked {
                ++i;
            }
        }
    }

    function _whitelistNewReferenceModules() internal {
        uint256 newReferenceModulesToWhitelistLength = newReferenceModulesToWhitelist.length;
        uint256 i;
        while (i < newReferenceModulesToWhitelistLength) {
            GOVERNANCE.lensHub_whitelistReferenceModule(newReferenceModulesToWhitelist[i], true);
            unchecked {
                ++i;
            }
        }
    }

    function _whitelistNewActionModules() internal {
        uint256 newActionModulesToWhitelistLength = newActionModulesToWhitelist.length;
        uint256 i;
        while (i < newActionModulesToWhitelistLength) {
            GOVERNANCE.lensHub_whitelistActionModule(newActionModulesToWhitelist[i], true);
            unchecked {
                ++i;
            }
        }
    }
}
