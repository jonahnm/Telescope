
mkdir ./baseboin

cd ./helloworld
make
codesign --remove-signature .theos/obj/debug/HelloWorld
cp .theos/obj/debug/HelloWorld ../baseboin
cd -

rm -rf "./basebin.tc"
chmod +x TrustCache*
arch=$(uname -m)
if [[ $arch == arm* ]] || [[ $arch == aarch64 ]]; then
./TrustCache create -v 2 "./basebin.tc" "./baseboin"
elif [[ $arch == x86_64* ]]; then
./TrustCache_x86_64 create -v 2 "./basebin.tc" "./baseboin"
fi
rm -rf ./baseboin 

