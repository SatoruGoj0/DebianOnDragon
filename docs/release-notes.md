Debian 13 (trixie) live + installer for the Lenovo IdeaPad Slim 3 15Q8X10 (83N3,
Snapdragon X X1-26-100). Linux v7.2 with the DebOnDragon devicetree.

**Not yet tested on hardware.** Read the install guide first:
https://github.com/SatoruGoj0/DebianOnDragon/blob/main/docs/install.md

- Write the ISO in **DD mode** (Rufus) and boot it from the **USB-A** port.
- Secure Boot must be off. Save your BitLocker recovery key first.
- Audio is disabled on purpose. Battery, USB-C and GPU need `debondragon-firmware` after install.
