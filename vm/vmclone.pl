#!/usr/bin/perl -w
#
# Copyright (c) 2007 VMware, Inc.  All rights reserved.
#

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../";

use VMware::VIRuntime;
use XML::LibXML;
use AppUtil::VMUtil;
use AppUtil::HostUtil;
use AppUtil::XMLInputUtil;

$Util::script_version = "1.0";

sub check_missing_value;

my %opts = (
   vmhost => {
      type => "=s",
      help => "The name of the host",
      required => 1,
   },
   vmname => {
      type => "=s",
      help => "The name of the Virtual Machine",
      required => 1,
   },
   vmname_destination => {
      type => "=s",
      help => "The name of the target virtual machine",
      required => 1,
   },
   filename => {
      type => "=s",
      help => "The name of the configuration specification file",
      required => 0,
      default => "../sampledata/vmclone.xml",
   },
   customize_guest => {
      type => "=s",
      help => "Flag to specify whether or not to customize guest: yes,no",
      required => 0,
      default => 'no',
   },
   customize_vm => {
      type => "=s",
      help => "Flag to specify whether or not to customize virtual machine: "
            . "yes,no",
      required => 0,
      default => 'no',
   },
   schema => {
      type => "=s",
      help => "The name of the schema file",
      required => 0,
      default => "../schema/vmclone.xsd",
   },
   datastore => {
      type => "=s",
      help => "Name of the Datastore",
      required => 0,
   },
);

Opts::add_options(%opts);
Opts::parse();
Opts::validate(\&validate);

Util::connect();

clone_vm();

Util::disconnect();


# Clone vm operation
# Gets destination host, compute resource views, and
# datastore info for creating the configuration
# specification to help create a clone of an existing
# virtual machine.
# ====================================================
sub clone_vm {
   my $vm_name = Opts::get_option('vmname');
   my $vm_views = Vim::find_entity_views(view_type => 'VirtualMachine',
                                        filter => {'name' =>$vm_name});
   if(@$vm_views) {
      foreach (@$vm_views) {
         my $host_name =  Opts::get_option('vmhost');
         my $host_view = Vim::find_entity_view(view_type => 'HostSystem',
                                         filter => {'name' => $host_name});

         if (!$host_view) {
            Util::trace(0, "Host '$host_name' not found\n");
            return;
         }
         # bug 449530
         my $disk_size = get_disksize();
         if($disk_size eq -1 || $disk_size eq "") {
            $disk_size = 0;
            my $devices = $_->config->hardware->device;
            foreach my $device (@$devices) {
               if (ref $device eq "VirtualDisk") {
                  $disk_size = $disk_size + $device->capacityInKB;
               }
            }
         }
	 my $network_dev_key;
	 my $devices = $_->config->hardware->device;
	 foreach my $device (@$devices) {
	 	if (ref $device eq "VirtualVmxnet3"){
			$network_dev_key = $device->key;
			last;
		}
	 }
         if ($host_view) {
            my $comp_res_view = Vim::get_view(mo_ref => $host_view->parent);
            my $ds_name = Opts::get_option('datastore');
            my %ds_info = HostUtils::get_datastore(host_view => $host_view,
                                     datastore => $ds_name,
                                     disksize => $disk_size);
            if ($ds_info{mor} eq 0) {
               if ($ds_info{name} eq 'datastore_error') {
                  Util::trace(0, "\nDatastore $ds_name not available.\n");
                  return;
               }
               if ($ds_info{name} eq 'disksize_error') {
                  Util::trace(0, "\nThe free space available is less than the"
                               . " specified disksize or the host"
                               . " is not accessible.\n");
                  return;
               }
            }

            my $relocate_spec =
            VirtualMachineRelocateSpec->new(datastore => $ds_info{mor},
                                          host => $host_view,
                                          pool => $comp_res_view->resourcePool);
            my $clone_name = Opts::get_option('vmname_destination');
            my $clone_spec ;
            my $config_spec;
            my $customization_spec;

            if ((Opts::get_option('customize_vm') eq "yes")
                && (Opts::get_option('customize_guest') ne "yes")) {
               $config_spec = get_config_spec('network_dev_key'=> $network_dev_key);
               $clone_spec = VirtualMachineCloneSpec->new(powerOn => 1,template => 0,
                                                       location => $relocate_spec,
                                                       config => $config_spec,
                                                       );
            }
            elsif ((Opts::get_option('customize_guest') eq "yes")
                && (Opts::get_option('customize_vm') ne "yes")) {
               $customization_spec = VMUtils::get_customization_spec
                                              (Opts::get_option('filename'));
               $clone_spec = VirtualMachineCloneSpec->new(
                                                   powerOn => 1,
                                                   template => 0,
                                                   location => $relocate_spec,
                                                   customization => $customization_spec,
                                                   );
            }
            elsif ((Opts::get_option('customize_guest') eq "yes")
                && (Opts::get_option('customize_vm') eq "yes")) {
               $customization_spec =VMUtils::get_customization_spec
                                              (Opts::get_option('filename'));
               $config_spec = get_config_spec('network_dev_key' => $network_dev_key);
               $clone_spec = VirtualMachineCloneSpec->new(
                                                   powerOn => 1,
                                                   template => 0,
                                                   location => $relocate_spec,
                                                   customization => $customization_spec,
                                                   config => $config_spec,
                                                   );
            }
            else {
               $clone_spec = VirtualMachineCloneSpec->new(
                                                   powerOn => 1,
                                                   template => 0,
                                                   location => $relocate_spec,
                                                   );
            }
            Util::trace (0, "\nCloning virtual machine '" . $vm_name . "' ...\n");

            eval {
               $_->CloneVM(folder => $_->parent,
                              name => Opts::get_option('vmname_destination'),
                              spec => $clone_spec);
               Util::trace (0, "\nClone '$clone_name' of virtual machine"
                             . " '$vm_name' successfully created.");
            };

            if ($@) {
               if (ref($@) eq 'SoapFault') {
                  if (ref($@->detail) eq 'FileFault') {
                     Util::trace(0, "\nFailed to access the virtual "
                                    ." machine files\n");
                  }
                  elsif (ref($@->detail) eq 'InvalidState') {
                     Util::trace(0,"The operation is not allowed "
                                   ."in the current state.\n");
                  }
                  elsif (ref($@->detail) eq 'NotSupported') {
                     Util::trace(0," Operation is not supported by the "
                                   ."current agent \n");
                  }
                  elsif (ref($@->detail) eq 'VmConfigFault') {
                     Util::trace(0,
                     "Virtual machine is not compatible with the destination host.\n");
                  }
                  elsif (ref($@->detail) eq 'InvalidPowerState') {
                     Util::trace(0,
                     "The attempted operation cannot be performed "
                     ."in the current state.\n");
                  }
                  elsif (ref($@->detail) eq 'DuplicateName') {
                     Util::trace(0,
                     "The name '$clone_name' already exists\n");
                  }
                  elsif (ref($@->detail) eq 'NoDisksToCustomize') {
                     Util::trace(0, "\nThe virtual machine has no virtual disks that"
                                  . " are suitable for customization or no guest"
                                  . " is present on given virtual machine" . "\n");
                  }
                  elsif (ref($@->detail) eq 'HostNotConnected') {
                     Util::trace(0, "\nUnable to communicate with the remote host, "
                                    ."since it is disconnected" . "\n");
                  }
                  elsif (ref($@->detail) eq 'UncustomizableGuest') {
                     Util::trace(0, "\nCustomization is not supported "
                                    ."for the guest operating system" . "\n");
                  }
                  else {
                     Util::trace (0, "Fault" . $@ . ""   );
                  }
               }
               else {
                  Util::trace (0, "Fault" . $@ . ""   );
               }
            }
         }
      }
   }
   else {
      Util::trace (0, "\nNo virtual machine found with name '$vm_name'\n");
   }
}

#Gets the config_spec for customizing the memory, number of cpu's
# and returns the spec
sub get_config_spec() {

   my %args = @_;
   my $network_dev_key = $args{'network_dev_key'};
   my $parser = XML::LibXML->new();
   my $tree = $parser->parse_file(Opts::get_option('filename'));
   my $root = $tree->getDocumentElement;
   my @cspec = $root->findnodes('Virtual-Machine-Spec');
   my $vmname ;
   my $vmhost  ;
   my $network;
   my $nic_allow_guest_control = 0;
   my $datastore;
   my $disksize = 4096;  # in KB;
   my $memory = 256;  # in MB;
   my $num_cpus = 1;
   my $nic_network;
   my $nic_poweron = 1;

   foreach (@cspec) {

      if ($_->findvalue('Network')) {
         $network = $_->findvalue('Network');
      }
      if ($_->findvalue('Memory')) {
         $memory = $_->findvalue('Memory');
      }
      if ($_->findvalue('Number-of-CPUS')) {
         $num_cpus = $_->findvalue('Number-of-CPUS');
      }
      $vmname = Opts::get_option('vmname_destination');
   }

# Retrieve network object
   my $network_view = Vim::find_entity_view(
         view_type => 'Network',
         filter => { 'name' => $network },
         );

   # New object which defines network backing for a virtual Ethernet card
   my $virtual_device_backing_info = VirtualEthernetCardNetworkBackingInfo->new(
                                                                            network => $network_view,
                                                                            deviceName => $network);

   # New object which contains information about connectable virtual devices
   my $vdev_connect_info = VirtualDeviceConnectInfo->new(
                                                        startConnected => $nic_poweron,
                                                        allowGuestControl => $nic_allow_guest_control,
                                                        connected => '1');
   # New object which define virtual device
   my $network_device = VirtualVmxnet3->new(
                                       key => $network_dev_key,
                                       backing => $virtual_device_backing_info,
                                       connectable => $vdev_connect_info);

   # New object which encapsulates change specifications for an individual virtual device
   my @device_config_spec = VirtualDeviceConfigSpec->new(
                                                     operation => VirtualDeviceConfigSpecOperation->new('edit'),
                                                     device => $network_device);

   # New object which encapsulates configuration settings when creating or reconfiguring a virtual machine
   my $vm_config_spec = VirtualMachineConfigSpec->new(
                                                  name => $vmname,
                                                  memoryMB => $memory,
                                                  numCPUs => $num_cpus,
                                                  deviceChange => \@device_config_spec);
 return $vm_config_spec;
}

sub get_disksize {
   my $disksize = -1;
   my $parser = XML::LibXML->new();

   eval {
      my $tree = $parser->parse_file(Opts::get_option('filename'));
      my $root = $tree->getDocumentElement;
      my @cspec = $root->findnodes('Virtual-Machine-Spec');

      foreach (@cspec) {
         $disksize = $_->findvalue('Disksize');
      }
   };
   return $disksize;
}

# check missing values of mandatory fields
sub check_missing_value {
   my $valid= 1;
   my $filename = Opts::get_option('filename');
   my $parser = XML::LibXML->new();
   my $tree = $parser->parse_file($filename);
   my $root = $tree->getDocumentElement;
   my @cust_spec = $root->findnodes('Customization-Spec');
   my $total = @cust_spec;
   if (!$cust_spec[0]->findvalue('IP')) {
      Util::trace(0,"\nERROR in '$filename':\n IP address value missing ");
      $valid = 0;
   }
   if (!$cust_spec[0]->findvalue('Netmask')) {
      Util::trace(0,"\nERROR in '$filename':\n Netmask value missing ");
      $valid = 0;
   }
   if (!$cust_spec[0]->findvalue('Gateway')) {
      Util::trace(0,"\nERROR in '$filename':\n Gateway value missing ");
      $valid = 0;
   }
   if (!$cust_spec[0]->findvalue('Domain')) {
      Util::trace(0,"\nERROR in '$filename':\n domain value missing ");
      $valid = 0;
   }
   return $valid;
}

sub validate {
   my $valid= 1;
   if ((Opts::get_option('customize_vm') eq "yes")
                || (Opts::get_option('customize_guest') eq "yes")) {

      $valid = XMLValidation::validate_format(Opts::get_option('filename'));
      if ($valid == 1) {
         $valid = XMLValidation::validate_schema(Opts::get_option('filename'),
	                                         Opts::get_option('schema'));
         if ($valid == 1) {
            $valid = check_missing_value();
         }
      }
   }

    if (Opts::option_is_set('customize_vm')) {
       if ((Opts::get_option('customize_vm') ne "yes")
             && (Opts::get_option('customize_vm') ne "no")) {
          Util::trace(0,"\nMust specify 'yes' or 'no' for customize_vm option");
          $valid = 0;
       }

    }
    if (Opts::option_is_set('customize_guest')) {
       if ((Opts::get_option('customize_guest') ne "yes")
             && (Opts::get_option('customize_guest') ne "no")) {
          Util::trace(0,"\nMust specify 'yes' or 'no' for customize_guest option");
          $valid = 0;
       }
    }
   return $valid;
}


# This subroutine constructs the customization spec for virtual machines.
# Input Parameters:
# ----------------
# filename      : The location of the input XML file. This file contains the
#                 various properties for customization spec
#
# Output:
# ------
# It returns the customization spec as per the input XML file
#
# sub get_customization_linux_spec {
#    my ($filename) = @_;
#    my $parser = XML::LibXML->new();
#    my $tree = $parser->parse_file($filename);
#    my $root = $tree->getDocumentElement;
#    my @cspec = $root->findnodes('Customization-Spec');
#
#    # Default Values
#    my $custType = "Win";
#    my $computername = "compname";
#    my $ipaddr;
#    my $netmask;
#    my @gateway;
#    my $domain;
#
#    my $autologon = 1;
#    my $timezone = "100";
#    my $username = "user";
#    my $userpassword = "user";
#    my $fullname = "user user";
#    my $autoMode = "perServer";
#    my $autoUsers = 5;
#    my $organization_name = "user's org";
#    my $productId = "XXXX-XXXX-XXXX-XXXX-XXXX";
#    #my $customization_fixed_ip;
#    #my @dnsServers;
#    #my $subnet;
#    #my $primaryWINS;
#    #my $secondaryWINS;
#    #my $dnsDomain;
#
#    foreach (@cspec) {
#      if ($_->findvalue('Cust-Type')) {
#         $custType = $_->findvalue('Cust-Type');
#      }
#      if ($_->findvalue('Virtual-Machine-Name')) {
#         $computername = $_->findvalue('Virtual-Machine-Name');
#      }
#      if ($_->findvalue('Domain')) {
#         $domain = $_->findvalue('Domain');
#      }
#       if ($_->findvalue('IP')) {
#          $ipaddr = $_->findvalue('IP');
#       }
#       if ($_->findvalue('Netmask')) {
#          $netmask = $_->findvalue('Netmask');
#       }
#       if ($_->findvalue('Gateway')) {
#          $gateway[0] = $_->findvalue('Gateway');
#       }
#       if ($_->findvalue('Auto-Logon')) {
#          $autologon = $_->findvalue('Auto-Logon');
#       }
#       if ($_->findvalue('Timezone')) {
#          $timezone = $_->findvalue('Timezone');
#       }
#       if ($_->findvalue('Domain-User-Name')) {
#          $username = $_->findvalue('Domain-User-Name');
#       }
#       if ($_->findvalue('Domain-User-Password')) {
#          $userpassword = $_->findvalue('Domain-User-Password');
#       }
#       if ($_->findvalue('Full-Name')) {
#          $fullname = $_->findvalue('Full-Name');
#       }
#       if ($_->findvalue('AutoMode')) {
#          $autoMode = $_->findvalue('AutoMode');
#       }
#       if ($_->findvalue('autoUsers')) {
#          $autoUsers = $_->findvalue('autoUsers');
#       }
#       if ($_->findvalue('Organization-Name')) {
#          $organization_name = $_->findvalue('Organization-Name');
#       }
#       if ($_->findvalue('productId')) {
#          $productId = $_->findvalue('productId');
#       }
#    }
#
#
#    # New object which is a collection of global IP settings for a virtual network adapter. In Linux, DNS server settings are global
#    my $customization_global_settings = CustomizationGlobalIPSettings->new();
#
#    my $cust_name = CustomizationFixedName->new (name => $computername);
#
#    my $cust_gui_unattended = CustomizationGuiUnattended->new(autoLogon => $autologon,
#                                    autoLogonCount => 0,
#                                    timeZone => $timezone);
#
#   my $password = CustomizationPassword->new(plainText=>"true", value=> $userpassword );
#
#   my $cust_identification = CustomizationIdentification->new(domainAdmin => $username,
#                                                                        domainAdminPassword => $password,
#                                                                        joinDomain => $domain);
#   my $customLicenseDataMode = new CustomizationLicenseDataMode($autoMode);
#   my $licenseFilePrintData = CustomizationLicenseFilePrintData->new(autoMode => $customLicenseDataMode,
#                                                                     autoUsers => $autoUsers);
#   my $cust_user_data = CustomizationUserData->new(computerName => $cust_name,  fullName => $fullname,  orgName => $organization_name,  productId => $productId);
#
#    my $cust_prep;
#
#    # New object which contains machine-wide settings that identify a Linux machine
#    if ( $custType eq "Win" ) {
#      $cust_prep =
#       CustomizationSysprep->new(guiUnattended => $cust_gui_unattended,
#                                 identification => $cust_identification,
#                                 licenseFilePrintData => $licenseFilePrintData,
#                                 userData => $cust_user_data);
#    } else {
#      $cust_prep =
#       CustomizationLinuxPrep->new(domain => $domain,
#                                 hostName => $cust_name);
#    }
#
#    # New object which define a static IP Address for the virtual network adapter
#    my $customization_fixed_ip = CustomizationFixedIp->new(ipAddress => $ipaddr);
#
#    # New object which define IP settings for a virtual network adapter
#    my $cust_ip_settings =
#       CustomizationIPSettings->new(
#                                gateway => \@gateway,
#                                subnetMask => $netmask,
#                                ip => $customization_fixed_ip);
#
#    # New object which associate a virtual network adapter with its IP settings
#    my $cust_adapter_mapping =
#       CustomizationAdapterMapping->new(adapter => $cust_ip_settings);
#
#    # New object, list of CustomizationAdapterMapping
#    my @cust_adapter_mapping_list = [$cust_adapter_mapping];
#
#    # New object which contains information required to customize a virtual machine guest OS
#    my $customization_spec =
#       CustomizationSpec->new(
#                          identity=>$cust_prep,
#                          globalIPSettings=>$customization_global_settings,
#                          nicSettingMap=>@cust_adapter_mapping_list);
#
#    return $customization_spec;
# }

__END__

=head1 NAME

vmclone.pl - Perform clone operation on virtual machine and
             customize operation on both virtual machine and the guest.

=head1 SYNOPSIS

 vmclone.pl [options]

=head1 DESCRIPTION

VI Perl command-line utility allows you to clone a virtual machine. You
can customize the virtual machine or the guest operating system as part
of the clone operation.

=head1 OPTIONS

=head2 GENERAL OPTIONS

=over

=item B<vmhost>

Required. Name of the host containing the virtual machine.

=item B<vmname>

Required. Name of the virtual machine whose clone is to be created.

=item B<vmname_destination>

Required. Name of the clone virtual machine which will be created.

=item B<datastore>

Optional. Name of a data center. If none is given, the script uses the default data center.

=back

=head2 CUSTOMIZE GUEST OPTIONS

=over

=item B<customize_guest>

Required. Customize guest is used to customize the network settings of the guest
operating system. Options are Yes/No.

=item B<filename>

Required. It is the name of the file in which values of parameters to be
customized is written e.g. --filename  clone_vm.xml.

=item B<schema>

Required. It is the name of the schema which validates the filename.

=back

=head2 CUSTOMIZE VM OPTIONS

=over

=item B<customize_vm>

Required. customize_vm is used to customize the virtual machine settings
like disksize, memory. If yes is written it will be customized.

=item B<filename>

Required. It is the name of the file in which values of parameters to be
customized is written e.g. --filename  clone_vm.xml.

=item B<schema>

Required. It is the name of the schema which validates the filename.

=back

=head2 INPUT PARAMETERS

=head3 GUEST CUSTOMIZATION

The parameters for customizing the guest os are specified in an XML
file. The structure of the input XML file is:

 <Specification>
  <Customization-Spec>
  </Customization-Spec>
 </Specification>

Following are the input parameters:

=over

=item B<Auto-Logon>

Required. Flag to specify whether auto logon should be enabled or disabled.

=item B<Virtual-Machine-Name>

Required. Name of the virtual machine to be created.

=item B<Timezone>

Required. Time zone property of guest OS.

=item B<Domain>

Required. The domain that the virtual machine should join.

=item B<Domain-User-Name>

Required. The domain user account used for authentication.

=item B<Domain-User-Password>

Required. The password for the domain user account used for authentication.

=item B<Full-Name>

Required. User's full name.

=item B<Organization-Name>

Required. User's organization.

=back

=head3 VIRTUAL MACHINE CUSTOMIZATION

The parameters for customizing the virtual machine are specified in an XML
file. The structure of the input XML file is:

   <Specification>
    <Config-Spec-Spec>
       <!--Several parameters like Guest-Id, Memory, Disksize, Number-of-CPUS etc-->
    </Config-Spec>
   </Specification>

Following are the input parameters:

=over

=item B<Guest-Id>

Required. Short guest operating system identifier.

=item B<Memory>

Required. Size of a virtual machine's memory, in MB.

=item B<Number-of-CPUS>

Required. Number of virtual processors in a virtual machine.

=back

See the B<vmcreate.pl> page for an example of a virtual machine XML file.

=head1 EXAMPLES

Making a clone without any customization:

 perl vmclone.pl --username username --password mypassword
                 --vmhost <hostname/ipaddress> --vmname DVM1 --vmname_destination DVM99
                 --url https://<ipaddress>:<port>/sdk/webService

If datastore is given:

 perl vmclone.pl --username username --password mypassword
                 --vmhost <hostname/ipaddress> --vmname DVM1 --vmname_destination DVM99
                 --url https://<ipaddress>:<port>/sdk/webService --datastore storage1

Making a clone and customizing the VM:

 perl vmclone.pl --username myusername --password mypassword
                 --vmhost <hostname/ipaddress> --vmname DVM1 --vmname_destination Clone_VM
                 --url https://<ipaddress>:<port>/sdk/webService --customize_vm yes
                 --filename clone_vm.xml --schema clone_schema.xsd

Making a clone and customizing the guestOS:

 perl vmclone.pl --username myuser --password mypassword --operation clone
                 --vmhost <hostname/ipaddress> --vmname DVM1 --vmname_destination DVM99
                 --url https://<ipaddress>:<port>/sdk/webService --customize_guest yes
                 --filename clone_vm.xml --schema clone_schema.xsd

Making a clone and customizing both guestos and VM:

 perl vmclone.pl --username myuser --password mypassword
                 --vmhost <hostname/ipaddress> --vmname DVM1 --vmname_destination DVM99
                 --url https://<ipaddress>:<port>/sdk/webService --customize_guest yes
                 --customize_vm yes --filename clone_vm.xml --schema clone_schema.xsd

All the parameters which are to be customized are written in the vmclone.xml file.

=head1 SUPPORTED PLATFORMS

All operations supported on VirtualCenter 2.0.1 or later.

To perform the clone operation, you must connect to a VirtualCenter server.
