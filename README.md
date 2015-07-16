# vmclone

Keeping this for documentation purposes. For a full set of scripts go [here](http://github.com/splashx/vmware-perl).

## Usage

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

# References

[Latest vmclone2.pl that now includes Linux cloning](https://communities.vmware.com/docs/DOC-12746)
