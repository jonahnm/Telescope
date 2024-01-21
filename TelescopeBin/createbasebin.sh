
mkdir ./baseboin

cd ./helloworld
make
cp .theos/obj/debug/arm64e/HelloWorld ../baseboin/
codesign -s - ../baseboin/HelloWorld
cd -

rm -rf "./basebin.tc"
chmod +x TrustCache*
arch=$(uname -m)
if [[ $arch == arm* ]] || [[ $arch == aarch64 ]]; then
./TrustCache create -v 2 basebin.tc baseboin
elif [[ $arch == x86_64* ]]; then
./TrustCache_x86_64 create -v 2 basebin.tc baseboin
fi


