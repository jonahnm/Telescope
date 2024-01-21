
mkdir ./baseboin

cd ./helloworld
make
codesign --remove-signature .theos/obj/debug/HelloWorld
cp .theos/obj/debug/HelloWorld ../baseboin

cd -

rm -rf "./basebin.tc"
./TrustCache create -v 2 "./basebin.tc" "./baseboin"

rm -rf ./baseboin 

