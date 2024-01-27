
sudo rm -rf ./baseboin
mkdir ./baseboin


#pluto (rootlesshooks)
cd Pluto
make
cp .theos/obj/pluto.dylib ../baseboin/
codesign -s - ../baseboin/pluto.dylib
cd ../

#neptune (systemhooks)
cd Neptune
make
cp Neptune.dylib ../baseboin/
codesign -s - ../baseboin/Neptune.dylib
cd ../

#jupiter (jbd)
cd Jupiter
make
cp .theos/obj/debug/Jupiter ../baseboin/
codesign -s - ../baseboin/Jupiter
ldid -Sent.xml ../baseboin/Jupiter
chmod +x ../baseboin/Jupiter
cd ../

rm -rf "./basebin.tc"
chmod +x ./TrustCache
chmod +x ./TrustCache_x86_64
cp opainject baseboin/
chmod +x baseboin/opainject
cp launchctl baseboin/
chmod +x baseboin/launchctl
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
