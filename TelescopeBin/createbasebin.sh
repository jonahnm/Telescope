
sudo rm -rf ./baseboin
mkdir ./baseboin


#pluto (rootlesshooks)
cd Pluto
make clean
make
cp .theos/obj/pluto.dylib ../baseboin/
codesign -s - ../baseboin/pluto.dylib
cd ../

#neptune (systemhooks)
cd Neptune
make clean
make
cp Neptune.dylib ../baseboin/
codesign -s - ../baseboin/Neptune.dylib
cd ../

#jupiter (jbd)
cd Jupiter
make clean
make
cp .theos/obj/debug/Jupiter.dylib ../baseboin/
sudo install_name_tool -change /Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate /var/jb/baseboin/libellekit.dylib ../baseboin/Jupiter.dylib
codesign -s - ../baseboin/Jupiter.dylib
chmod +x ../baseboin/Jupiter.dylib
cd ../

rm -rf "./basebin.tc"
chmod +x ./TrustCache
chmod +x ./TrustCache_x86_64
cp opainject baseboin/
chmod +x baseboin/opainject
cp launchctl baseboin/
chmod +x baseboin/launchctl
cp libellekit.dylib baseboin/
cp -r LaunchDaemons baseboin/
sudo chown -hR root:wheel baseboin
arch=$(uname -m)
if [[ $arch == arm* ]] || [[ $arch == aarch64 ]]; then
./TrustCache create -v 2 basebin.tc baseboin
elif [[ $arch == x86_64* ]]; then
./TrustCache_x86_64 create -v 2 basebin.tc baseboin
fi

rm basebin.tar
tar -cvf basebin.tar baseboin

cd -
