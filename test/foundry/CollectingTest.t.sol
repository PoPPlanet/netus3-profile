// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import './base/BaseTest.t.sol';
import './helpers/SignatureHelpers.sol';
import './helpers/CollectingHelpers.sol';

contract SigSetup {
    uint256 nonce;
    uint256 deadline;

    function setUp() public virtual {
        nonce = 0;
        deadline = type(uint256).max;
    }
}

// TODO add check for _initialize() called for fork tests - check name and symbol set

contract CollectingTest_Base is BaseTest, SignatureHelpers, CollectingHelpers, SigSetup {
    function _mockCollect() internal virtual returns (uint256) {
        return
            _collect(
                mockCollectData.collector,
                mockCollectData.profileId,
                mockCollectData.pubId,
                mockCollectData.data
            );
    }

    function _mockCollectWithSig(address delegatedSigner, uint256 signerPrivKey)
        internal
        virtual
        returns (uint256)
    {
        bytes32 digest = _getCollectTypedDataHash(
            mockCollectData.profileId,
            mockCollectData.pubId,
            mockCollectData.data,
            nonce,
            deadline
        );

        return
            _collectWithSig(
                _buildCollectWithSigData(
                    delegatedSigner,
                    mockCollectData,
                    _getSigStruct(signerPrivKey, digest, deadline)
                )
            );
    }

    function setUp() public virtual override(SigSetup, TestSetup) {
        TestSetup.setUp();
        SigSetup.setUp();

        vm.prank(profileOwner);
        hub.post(mockPostData);
    }
}

contract CollectingTest_Generic is CollectingTest_Base {
    function setUp() public override {
        CollectingTest_Base.setUp();
    }

    // NEGATIVES

    function testCannotCollectIfNotExecutor() public {
        vm.expectRevert(Errors.ExecutorInvalid.selector);
        _mockCollect();
    }

    function testCannotCollectIfNonexistantPub() public {
        mockCollectData.pubId = 2;
        // Check that the publication doesn't exist.
        assertEq(_getPub(mockCollectData.profileId, mockCollectData.pubId).profileIdPointed, 0);

        vm.startPrank(profileOwner);
        vm.expectRevert(Errors.PublicationDoesNotExist.selector);
        _mockCollect();
        vm.stopPrank();
    }

    function testCannotCollectIfZeroPub() public {
        mockCollectData.pubId = 0;
        // Check that the publication doesn't exist.
        assertEq(_getPub(mockCollectData.profileId, mockCollectData.pubId).profileIdPointed, 0);

        vm.startPrank(profileOwner);
        vm.expectRevert(Errors.PublicationDoesNotExist.selector);
        _mockCollect();
        vm.stopPrank();
    }

    // SCENARIOS

    function testCollect() public {
        _checkCollectNFTBefore();

        vm.startPrank(profileOwner);
        uint256 nftId = _mockCollect();
        vm.stopPrank();

        _checkCollectNFTAfter(nftId);
    }

    function testCollectMirror() public {
        _checkCollectNFTBefore();

        vm.startPrank(profileOwner);
        hub.mirror(mockMirrorData);
        uint256 nftId = _mockCollect();
        vm.stopPrank();

        _checkCollectNFTAfter(nftId);
    }

    function testExecutorCollect() public {
        _checkCollectNFTBefore();

        // delegate power to executor
        vm.prank(profileOwner);
        _setDelegatedExecutorApproval(otherSigner, true);

        // collect from executor
        vm.startPrank(otherSigner);
        uint256 nftId = _mockCollect();
        vm.stopPrank();

        _checkCollectNFTAfter(nftId);
    }

    function testExecutorCollectMirror() public {
        _checkCollectNFTBefore();

        // mirror, then delegate power to executor
        vm.startPrank(profileOwner);
        hub.mirror(mockMirrorData);
        _setDelegatedExecutorApproval(otherSigner, true);
        vm.stopPrank();

        // collect from executor
        vm.startPrank(otherSigner);
        uint256 nftId = _mockCollect();
        vm.stopPrank();

        _checkCollectNFTAfter(nftId);
    }
}

contract CollectingTest_WithSig is CollectingTest_Base {
    function setUp() public override {
        CollectingTest_Base.setUp();
    }

    // NEGATIVES

    function testCannotCollectWithSigIfNotExecutor() public {
        vm.expectRevert(Errors.ExecutorInvalid.selector);
        _mockCollectWithSig({delegatedSigner: otherSigner, signerPrivKey: otherSignerKey});
    }

    function testCannotCollectWithSigIfNonexistantPub() public {
        mockCollectData.pubId = 2;
        // Check that the publication doesn't exist.
        assertEq(_getPub(mockCollectData.profileId, mockCollectData.pubId).profileIdPointed, 0);

        vm.expectRevert(Errors.PublicationDoesNotExist.selector);
        _mockCollectWithSig({delegatedSigner: address(0), signerPrivKey: profileOwnerKey});
    }

    function testCannotCollectWithSigIfZeroPub() public {
        mockCollectData.pubId = 0;
        // Check that the publication doesn't exist.
        assertEq(_getPub(mockCollectData.profileId, mockCollectData.pubId).profileIdPointed, 0);

        vm.expectRevert(Errors.PublicationDoesNotExist.selector);
        _mockCollectWithSig({delegatedSigner: address(0), signerPrivKey: profileOwnerKey});
    }

    function testCannotCollectWithSigOnExpiredDeadline() public {
        deadline = block.timestamp - 1;
        vm.expectRevert(Errors.SignatureExpired.selector);
        _mockCollectWithSig({delegatedSigner: address(0), signerPrivKey: profileOwnerKey});
    }

    function testCannotCollectWithSigOnInvalidNonce() public {
        nonce = 5;
        vm.expectRevert(Errors.SignatureInvalid.selector);
        _mockCollectWithSig({delegatedSigner: address(0), signerPrivKey: profileOwnerKey});
    }

    // SCENARIOS

    function testCollectWithSig() public {
        _checkCollectNFTBefore();

        uint256 nftId = _mockCollectWithSig({
            delegatedSigner: address(0),
            signerPrivKey: profileOwnerKey
        });

        _checkCollectNFTAfter(nftId);
    }

    function testCollectWithSigMirror() public {
        _checkCollectNFTBefore();

        vm.prank(profileOwner);
        hub.mirror(mockMirrorData);

        uint256 nftId = _mockCollectWithSig({
            delegatedSigner: address(0),
            signerPrivKey: profileOwnerKey
        });

        _checkCollectNFTAfter(nftId);
    }

    function testExecutorCollectWithSig() public {
        _checkCollectNFTBefore();

        // delegate power to executor
        vm.prank(profileOwner);
        _setDelegatedExecutorApproval(otherSigner, true);

        // collect from executor
        uint256 nftId = _mockCollectWithSig({
            delegatedSigner: otherSigner,
            signerPrivKey: otherSignerKey
        });

        _checkCollectNFTAfter(nftId);
    }

    function testExecutorCollectWithSigMirror() public {
        _checkCollectNFTBefore();

        // mirror, then delegate power to executor
        vm.startPrank(profileOwner);
        hub.mirror(mockMirrorData);
        _setDelegatedExecutorApproval(otherSigner, true);
        vm.stopPrank();

        // collect from executor
        uint256 nftId = _mockCollectWithSig({
            delegatedSigner: otherSigner,
            signerPrivKey: otherSignerKey
        });

        _checkCollectNFTAfter(nftId);
    }
}
