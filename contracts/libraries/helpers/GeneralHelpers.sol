// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import {DataTypes} from '../DataTypes.sol';
import {Errors} from '../Errors.sol';

import '../Constants.sol';

/**
 * @title Helpers
 * @author Lens Protocol
 *
 * @notice This is a library that contains helper internal functions used by both the Hub and the GeneralLib.
 */
library GeneralHelpers {
    /**
     * @notice This helper function just returns the pointed publication if the passed publication is a mirror,
     * otherwise it returns the passed publication.
     *
     * @param profileId The token ID of the profile that published the given publication.
     * @param pubId The publication ID of the given publication.
     *
     * @return tuple First, the pointed publication's publishing profile ID, second, the pointed publication's ID, and third, the
     * pointed publication's collect module. If the passed publication is not a mirror, this returns the given publication.
     */
    function getPointedIfMirror(uint256 profileId, uint256 pubId)
        internal
        view
        returns (
            uint256,
            uint256,
            address
        )
    {
        DataTypes.PublicationStruct storage _publication = getPublicationStruct(profileId, pubId);
        address collectModule = _publication.collectModule;
        if (collectModule != address(0)) {
            // We rely on the collect module being zero for classifying mirrors or non-existent publications so, if it
            // is not zero, the publication is not a mirror, thus we return the original pubId and profileId.
            return (profileId, pubId, collectModule);
        } else {
            // The publication is either a mirror or a non-existent one. We determine that by checking the pointed
            // profile and publication IDs.
            uint256 pointedProfileId = _publication.pointedProfileId;
            // We validate existence here as an optimization, so validating in calling contracts is unnecessary.
            // As this publication is expected to be a mirror, it needs to be pointing to an existing publication,
            // otherwise this publication does not exist.
            if (pointedProfileId == 0) {
                revert Errors.PublicationDoesNotExist();
            }
            uint256 pointedPubId = _publication.pointedPubId;
            return (
                pointedProfileId,
                pointedPubId,
                getPublicationStruct(pointedProfileId, pointedPubId).collectModule
            );
        }
    }

    function validatePointedPub(uint256 profileId, uint256 pubId) internal view {
        // If it is pointing to itself it will fail because it will return non-existent type.
        DataTypes.PublicationType pointedPubType = getPublicationType(profileId, pubId);
        if (
            pointedPubType == DataTypes.PublicationType.Nonexistent ||
            pointedPubType == DataTypes.PublicationType.Mirror
        ) {
            revert Errors.InvalidPointedPub();
        }
    }

    /**
     * @dev This fetches the owner address for a given token ID. Note that this does not check and
     * revert upon loading a zero address.
     *
     * However, this function is only used if the result is compared to the caller or a recovered signer,
     * which is already checked for the zero address.
     */
    function unsafeOwnerOf(uint256 tokenId) internal view returns (address) {
        address owner;
        assembly {
            mstore(0, tokenId)
            mstore(32, TOKEN_DATA_MAPPING_SLOT)
            let slot := keccak256(0, 64)
            // This bit shift is necessary to remove the packing from the variable.
            owner := shr(96, shl(96, sload(slot)))
        }
        return owner;
    }

    function ownerOf(uint256 tokenId) internal view returns (address) {
        address owner = unsafeOwnerOf(tokenId);
        if (owner == address(0)) {
            revert Errors.TokenDoesNotExist();
        }
        return owner;
    }

    function validateAddressIsProfileOwner(address expectedProfileOwner, uint256 profileId)
        internal
        view
    {
        if (expectedProfileOwner != ownerOf(profileId)) {
            revert Errors.NotProfileOwner();
        }
    }

    function validateAddressIsProfileOwnerOrDelegatedExecutor(
        address expectedOwnerOrDelegatedExecutor,
        uint256 profileId
    ) internal view {
        if (expectedOwnerOrDelegatedExecutor != ownerOf(profileId)) {
            validateAddressIsDelegatedExecutor({
                expectedDelegatedExecutor: expectedOwnerOrDelegatedExecutor,
                delegatorProfileId: profileId
            });
        }
    }

    function validateAddressIsDelegatedExecutor(
        address expectedDelegatedExecutor,
        uint256 delegatorProfileId
    ) internal view {
        if (!isExecutorApproved(delegatorProfileId, expectedDelegatedExecutor)) {
            revert Errors.ExecutorInvalid();
        }
    }

    function validateCollectModuleWhitelisted(address collectModule) internal view {
        _validateModuleWhitelisted({
            whitelistMappingSlot: COLLECT_MODULE_WHITELIST_MAPPING_SLOT,
            moduleAddress: collectModule,
            errorSelector: Errors.CollectModuleNotWhitelisted.selector
        });
    }

    function validateReferenceModuleWhitelisted(address referenceModule) internal view {
        _validateModuleWhitelisted({
            whitelistMappingSlot: REFERENCE_MODULE_WHITELIST_MAPPING_SLOT,
            moduleAddress: referenceModule,
            errorSelector: Errors.ReferenceModuleNotWhitelisted.selector
        });
    }

    function getDelegatedExecutorsConfig(uint256 delegatorProfileId)
        internal
        pure
        returns (DataTypes.DelegatedExecutorsConfig storage)
    {
        DataTypes.DelegatedExecutorsConfig storage _delegatedExecutorsConfig;
        assembly {
            mstore(0, delegatorProfileId)
            mstore(32, DELEGATED_EXECUTOR_CONFIG_MAPPING_SLOT)
            _delegatedExecutorsConfig.slot := keccak256(0, 64)
        }
        return _delegatedExecutorsConfig;
    }

    function isExecutorApproved(uint256 delegatorProfileId, address executor)
        internal
        view
        returns (bool)
    {
        DataTypes.DelegatedExecutorsConfig
            storage _delegatedExecutorsConfig = getDelegatedExecutorsConfig(delegatorProfileId);
        return
            _delegatedExecutorsConfig.isApproved[_delegatedExecutorsConfig.configNumber][executor];
    }

    /**
     * @dev Returns either the profile owner or the delegated signer if valid.
     */
    function getOriginatorOrDelegatedExecutorSigner(uint256 profileId, address delegatedSigner)
        internal
        view
        returns (address)
    {
        if (delegatedSigner == address(0)) {
            return ownerOf(profileId);
        } else {
            validateAddressIsDelegatedExecutor({
                expectedDelegatedExecutor: delegatedSigner,
                delegatorProfileId: profileId
            });
            return delegatedSigner;
        }
    }

    function validateNotBlocked(uint256 profile, uint256 byProfile) internal view {
        bool isBlocked;
        assembly {
            mstore(0, byProfile)
            mstore(32, BLOCK_STATUS_MAPPING_SLOT)
            let blockStatusByProfileSlot := keccak256(0, 64)
            mstore(0, profile)
            mstore(32, blockStatusByProfileSlot)
            isBlocked := sload(keccak256(0, 64))
        }
        if (isBlocked) {
            revert Errors.Blocked();
        }
    }

    function getPublicationType(uint256 profileId, uint256 pubId)
        internal
        view
        returns (DataTypes.PublicationType)
    {
        DataTypes.PublicationStruct storage _publication = getPublicationStruct(profileId, pubId);
        DataTypes.PublicationType pubType = _publication.pubType;
        if (uint8(pubType) == 0) {
            // If publication type is 0, we check using the legacy rules.
            if (_publication.pointedProfileId != 0) {
                // It is pointing to a publication, so it can be either a comment or a mirror, depending on if it has a
                // collect module or not.
                if (_publication.collectModule == address(0)) {
                    return DataTypes.PublicationType.Mirror;
                } else {
                    return DataTypes.PublicationType.Comment;
                }
            } else if (_publication.collectModule != address(0)) {
                return DataTypes.PublicationType.Post;
            }
        }
        return pubType;
    }

    function getPublicationStruct(uint256 profileId, uint256 pubId)
        internal
        pure
        returns (DataTypes.PublicationStruct storage)
    {
        DataTypes.PublicationStruct storage _publication;
        assembly {
            mstore(0, profileId)
            mstore(32, PUB_BY_ID_BY_PROFILE_MAPPING_SLOT)
            mstore(32, keccak256(0, 64))
            mstore(0, pubId)
            _publication.slot := keccak256(0, 64)
        }
        return _publication;
    }

    function getProfileStruct(uint256 profileId)
        internal
        pure
        returns (DataTypes.ProfileStruct storage)
    {
        DataTypes.ProfileStruct storage _profile;
        assembly {
            mstore(0, profileId)
            mstore(32, PROFILE_BY_ID_MAPPING_SLOT)
            _profile.slot := keccak256(0, 64)
        }
        return _profile;
    }

    function validateReferrerAndGetReferrerPubType(
        uint256 referrerProfileId,
        uint256 referrerPubId,
        uint256 profileId,
        uint256 pubId
    ) internal view returns (DataTypes.PublicationType) {
        if (referrerProfileId == 0 && referrerPubId == 0) {
            // No referrer was passed.
            return DataTypes.PublicationType.Nonexistent;
        }

        if (
            // Cannot pass itself as a referrer.
            referrerProfileId == profileId && referrerPubId == pubId
        ) {
            revert Errors.InvalidReferrer();
        }

        DataTypes.PublicationType referrerPubType = GeneralHelpers.getPublicationType(
            referrerProfileId,
            referrerPubId
        );

        if (referrerPubType == DataTypes.PublicationType.Mirror) {
            _validateReferrerAsMirror(referrerProfileId, referrerPubId, profileId, pubId);
        } else if (
            referrerPubType == DataTypes.PublicationType.Comment ||
            referrerPubType == DataTypes.PublicationType.Quote
        ) {
            _validateReferrerAsCommentOrQuote(referrerProfileId, referrerPubId, profileId, pubId);
        } else {
            // Referrarls are only supported for mirrors, comments and quotes, not for posts.
            revert Errors.InvalidReferrer();
        }

        return referrerPubType;
    }

    function _validateReferrerAsMirror(
        uint256 referrerProfileId,
        uint256 referrerPubId,
        uint256 profileId,
        uint256 pubId
    ) private view {
        DataTypes.PublicationStruct storage _referrerMirror = GeneralHelpers.getPublicationStruct(
            referrerProfileId,
            referrerPubId
        );
        if (
            // A mirror can only be a referrer of a publication if it is pointing to it.
            _referrerMirror.pointedProfileId != profileId || _referrerMirror.pointedPubId != pubId
        ) {
            revert Errors.InvalidReferrer();
        }
    }

    /**
     * @dev Validates that the referrer publication and the interacted publilcation are linked.
     *
     * @param referrerProfileId The profile id of the referrer.
     * @param referrerPubId The publication id of the referrer.
     * @param profileId This is the ID of the profile who authored the publication being collected or referenced.
     * @param pubId This is the pub user collects or references.
     */
    function _validateReferrerAsCommentOrQuote(
        uint256 referrerProfileId,
        uint256 referrerPubId,
        uint256 profileId,
        uint256 pubId
    ) private view {
        DataTypes.PublicationStruct storage _referrerPub = GeneralHelpers.getPublicationStruct(
            referrerProfileId,
            referrerPubId
        );
        DataTypes.PublicationType typeOfPubPointedByReferrer = GeneralHelpers.getPublicationType(
            profileId,
            pubId
        );
        // We already know that the publication being collected/referenced is not a mirror nor a non-existent one.
        if (typeOfPubPointedByReferrer == DataTypes.PublicationType.Post) {
            // If the publication collected/referenced is a post, the referrer comment/quote must have it as root.
            if (_referrerPub.rootProfileId != profileId || _referrerPub.rootPubId != pubId) {
                revert Errors.InvalidReferrer();
            }
        } else {
            // The publication collected/referenced is a comment or a quote.
            DataTypes.PublicationStruct storage _pubPointedByReferrer = GeneralHelpers
                .getPublicationStruct(profileId, pubId);
            // The referrer publication and the collected/referenced publication must share the same root.
            if (
                _referrerPub.rootProfileId != _pubPointedByReferrer.rootProfileId ||
                _referrerPub.rootPubId != _pubPointedByReferrer.rootPubId
            ) {
                revert Errors.InvalidReferrer();
            }
        }
    }

    function _validateModuleWhitelisted(
        uint256 whitelistMappingSlot,
        address moduleAddress,
        bytes4 errorSelector
    ) private view {
        bool isModuleWhitelisted;
        assembly {
            mstore(0, moduleAddress)
            mstore(32, whitelistMappingSlot)
            isModuleWhitelisted := sload(keccak256(0, 64))
        }
        if (!isModuleWhitelisted) {
            assembly {
                mstore(0, errorSelector)
                revert(0, 4)
            }
        }
    }
}