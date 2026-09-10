#!/bin/bash
# OC USB MEDIA
# (c) Copyright 2026 chris1111, All Right Reserved.
# This will create a Apple Bundle App OC USB MEDIA

PARENTDIR=$(dirname "$0")
cd "$PARENTDIR"

# Vars
apptitle="OC USB MEDIA.app"
version="1.0"

find . -name '.DS_Store' -type f -delete

# Build Project
xcodebuild -project "OCUSBMEDIA.xcodeproj" -alltargets -configuration Release build
sleep 3

# Delete build if exist
rm -rf ./Packages/OpenCore-Package
rm -rf /tmp/PackageDIR
rm -rf ./Packages/OpenCore-Package.pkg
sleep 1

mkdir -p ./Packages/OpenCore-Package/BUILD-PACKAGE
mkdir -p /tmp/PackageDIR

# Create Packages with pkgbuild
pkgbuild --root ./Packages/OC-EFI --scripts ./Packages/ScriptEFI --identifier com.opencorePackage.OpenCorePackage.pkg --version 1.0 --install-location /Private/tmp/EFIROOTDIR ./Packages/OpenCore-Package/BUILD-PACKAGE/opencorePackage.pkg

sleep 2

# Expend the Packages with pkgutil
pkgutil --expand ./Packages/OpenCore-Package/BUILD-PACKAGE/opencorePackage.pkg /tmp/PackageDIR/opencorePackage.pkg
sleep 3

# Copy resources and distribution
cp -r ./Packages/Distribution ./Packages/OpenCore-Package/BUILD-PACKAGE/Distribution.xml
cp -rp ./Packages/Resources ./Packages/OpenCore-Package/BUILD-PACKAGE/
sleep 2

mkdir -p ./Installer
echo "
= = = = = = = = = = = = = = = = = = = = = = = = = =
Create final Package with Productbuild "
sleep 3

# Create final Package with Productbuild
productbuild --distribution "./Packages/OpenCore-Package/BUILD-PACKAGE/Distribution.xml" \
--package-path "./Packages/OpenCore-Package/BUILD-PACKAGE/" \
--resources "./Packages/OpenCore-Package/BUILD-PACKAGE/Resources" \
"./Installer/OpenCore.pkg"

echo " "
rm -rf ./Packages/OpenCore-Package
echo "** BUILD PACKAGE SUCCEEDED **"
sleep 1

cp -rp ./Installer "./build/Release/OC USB MEDIA.app/Contents/Resources"
sleep 1

rm -rf ./Installer
open ./build/Release

echo " = = = = = = = = = = = = = = = = = = = = = = = = = 
 $apptitle completed
= = = = = = = = = = = = = = = = = = = = = = = = =  "