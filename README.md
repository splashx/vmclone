# vmclone


## Prepping the enviroment

### OSX

#### Perl dependencies
```bash
$ sudo cpan Class::MethodMaker Crypt::SSLeay SOAP::Lite
```

_UUID installation is broken via CPAN, plus the CPAN version is newer - vmware requires 0.03 which is ANCIENT, installing it manually (there will be some warnings, nothing fatal)_

```bash
$ curl -s http://www.cpan.org/authors/id/C/CF/CFABER/UUID-0.03.tar.gz -o UUID-0.03.tar.gz && \
tar -xzvf UUID-0.03.tar.gz && \
cd UUID-0.03 && \
perl Makefile.PL && \
make -Wpointer-sign && \
sudo make install
```
#### VI Perl Toolkit Release 1.6
Download the VI Perl Toolkit source code from [here](https://my.vmware.com/group/vmware/details?productId=20&downloadGroup=VI-PERL-TK160-OS) and extract it (the folder vmware-viperl-distrib is created).

```bash
$ cd vmware-viperl-distrib && \
make && \
sudo make install
```

_when running from the command line, set the enviroment variable to ignore trusted cert (libwww-perl will fail on self-signed certs). Make sure you know what this means!_
```
$ export PERL_LWP_SSL_VERIFY_HOSTNAME=0
```
_Or pass the root CA file path via PERL_LWP_SSL_CA_PATH:_
```
$ export PERL_LWP_SSL_CA_PATH=/path/to/ca/certs
```

### Usage

```bash
$ perl vmclone2.pl --customize_guest yes \
--username "username@vsphere.local" \
--password $PASSWORD \
--vmhost $VM_HOST \
--vmname $VM_TEMPLATE_NAME \
--vmname_destination $NEW_VM_NAME \
--url https://$VCENTER_IP/sdk/vimService \
--filename ../sampledata/vmclone.xml \
--schema ../schema/vmclone.xsd
```
