// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Mudiverse.sol";

contract MudiverseTest is Test {
    Mudiverse public mudiverse;

    function setUp() public {
        mudiverse = new Mudiverse();

        Mudiverse.Location memory location1 = Mudiverse.Location("West of House","You are standing in an open duck pasture west of a white house, with an open front door. There is a small mailbox here.",true,0,0,2,0);
        mudiverse.setMetadata(1,location1);

        Mudiverse.Location memory location2 = Mudiverse.Location("Quaint Farmhouse","You're inside a cozy farmhouse with sapphic cottagecore vibes. Outside is west. Doors to the rest of the house are north and south.",false,3,0,0,1);
        mudiverse.setMetadata(2,location2);
    }

    function testLook() public {
        mudiverse.look();

        assertEq(mudiverse.positionId(), 1);
    }

    function testMovement() public {
        mudiverse.east();
        assertEq(mudiverse.positionId(), 2);

        mudiverse.west();
        assertEq(mudiverse.positionId(), 1);
    }

    function testSetMetadata() public {
        Mudiverse.Location memory location = Mudiverse.Location("Farmhouse Kitchen", "The kitchen is full of cartoon ducks laying eggs and turning them into omlettes. You can leave to the south.", false, 0,2,0,0);
        mudiverse.setMetadata(3,location);
    }

    function testSetFrozen() public {
        mudiverse.setFrozen(1, true);
        bool isFrozen = mudiverse.frozen(1);
        assertEq(isFrozen, true);

        mudiverse.setFrozen(1, false);
        isFrozen = mudiverse.frozen(1);
        assertEq(isFrozen, false);
    }
}
