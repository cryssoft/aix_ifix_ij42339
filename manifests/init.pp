#
#  2022/12/14 - cp - The first of the individual AIX ifix modules to try to get
#		the IJ42339 module loading properly on just AIX (not VIOS yet)
#		boxes with the proper version of the ifix applied to the
#		patch level of AIX where it belongs.
#
#		cp - The lowercase IJ in the name is sub-optimal, but there seems
#		to be an issue with the role::{hostname} include statement that's
#		explicitly lowercasing the name.  Gotta go with the flow.
#
#  NOTES:	This depends on facts supplied by the aix_vios_facts and
#		aix_ifix_facts modules to work.
#
#  NOTES:   Digging into some other ifixes, it looks like there are some complex
#       cases where the AIX patch level as a whole is not enough to determine
#       which spin of an ifix applies (IJ43869 has 2 spins for 7.2.5.3 based on
#       the specific file set level that's being patched).  Without more custom
#       facts, I'm not sure how I'd solve that in a Puppet module.
#
#-------------------------------------------------------------------------------
#
#  From Advisory.asc:
#
#       Fileset                 Lower Level  Upper Level KEY 
#       ---------------------------------------------------------
#       bos.rte.control         7.2.4.0      7.2.4.5     key_w_fs
#       bos.rte.control         7.2.5.0      7.2.5.4     key_w_fs
#       bos.rte.control         7.2.5.100    7.2.5.101   key_w_fs
#       bos.rte.control         7.2.5.200    7.2.5.200   key_w_fs
#       bos.rte.control         7.3.0.0      7.3.0.1     key_w_fs
#
#       AIX Level APAR     Availability  SP        KEY
#       -----------------------------------------------------
#       7.2.4     IJ42381  **            N/A       key_w_apar
#       7.2.5     IJ42339  **            SP06      key_w_apar
#       7.3.0     IJ42341  **            SP04      key_w_apar
#
#       VIOS Level APAR    Availability  SP        KEY
#       -----------------------------------------------------
#       3.1.1      IJ42381 **            N/A       key_w_apar
#       3.1.2      IJ42378 **            3.1.2.60  key_w_apar
#       3.1.3      IJ42379 **            3.1.3.40  key_w_apar <- we are here
#       3.1.4      IJ42339 **            3.1.4.20  key_w_apar
#
#       AIX Level  Interim Fix (*.Z)         KEY
#       ----------------------------------------------
#       7.2.4.4    IJ42381s6a.220909.epkg.Z  key_w_fix
#       7.2.4.5    IJ42381s6a.220909.epkg.Z  key_w_fix
#       7.2.4.6    IJ42381s6a.220909.epkg.Z  key_w_fix
#       7.2.5.2    IJ42339s2a.220909.epkg.Z  key_w_fix <- we are here
#       7.2.5.3    IJ42339s4a.220907.epkg.Z  key_w_fix <- we are here
#       7.2.5.4    IJ42339s4a.220907.epkg.Z  key_w_fix <- we are here
#       7.2.5.5    IJ42339s5a.221212.epkg.Z  key_w_fix
#       7.3.0.1    IJ42341s2a.220907.epkg.Z  key_w_fix
#       7.3.0.2    IJ42341s2a.220907.epkg.Z  key_w_fix
#
#-------------------------------------------------------------------------------
#
class aix_ifix_ij42339 {

    #  Make sure we can get to the ::staging module (deprecated ?)
    include ::staging

    #  This only applies to AIX and maybe VIOS in later versions
    if ($::facts['osfamily'] == 'AIX') {

        #  Set the ifix ID up here to be used later in various names
        $ifixName = 'IJ42339'

        #  Make sure we create/manage the ifix staging directory
        require profile::aix_file_opt_ifixes

        #
        #  For now, we're skipping anything that reads as a VIO server.
        #  We have no matching versions of this ifix / VIOS level installed.
        #
        unless ($::facts['aix_vios']['is_vios']) {

            #
            #  Friggin' IBM...  The ifix ID that we find and capture in the fact has the
            #  suffix allready applied.
            #
            if ($::facts['kernelrelease'] == '7200-05-02-2114') {
                $ifixSuffix = 's2a'
                $ifixBuildDate = '220909'
            }
            else {
                if ($::facts['kernelrelease'] in ['7200-05-03-2148', '7200-05-04-2220']) {
                    $ifixSuffix = 's4a'
                    $ifixBuildDate = '220907'
                }
                else {
                    if ($::facts['kernelrelease'] == '7200-05-05-2246') {
                        $ifixSuffix = 's5a'
                        $ifixBuildDate = '221212'
                    }
                    else {
                        $ifixSuffix = 'unknown'
                        $ifixBuildDate = 'unknown'
                    }
                }
            }

            #  Add the name and suffix to make something we can find in the fact
            $ifixFullName = "${ifixName}${ifixSuffix}"

            #  If we set our $ifixSuffix and $ifixBuildDate, we'll continue
            if (($ifixSuffix != 'unknown') and ($ifixBuildDate != 'unknown')) {

                #  Don't bother with this if it's already showing up installed
                unless ($ifixFullName in $::facts['aix_ifix'].keys) {
 
                    #  Build up the complete name of the ifix staging source and target
                    $ifixStagingSource = "puppet:///modules/profile/${ifixName}${ifixSuffix}.${ifixBuildDate}.epkg.Z"
                    $ifixStagingTarget = "/opt/ifixes/${ifixName}${ifixSuffix}.${ifixBuildDate}.epkg.Z"

                    #  Stage it
                    staging::file { "$ifixStagingSource" :
                        source  => "$ifixStagingSource",
                        target  => "$ifixStagingTarget",
                        before  => Exec["emgr-install-${ifixName}"],
                    }

                    #  GAG!  Use an exec resource to install it, since we have no other option yet
                    exec { "emgr-install-${ifixName}":
                        path     => '/bin:/sbin:/usr/bin:/usr/sbin:/etc',
                        command  => "/usr/sbin/emgr -e $ifixStagingTarget",
                        unless   => "/usr/sbin/emgr -l -L $ifixFullName",
                    }

                    #  Explicitly define the dependency relationships between our resources
                    File['/opt/ifixes']->Staging::File["$ifixStagingSource"]->Exec["emgr-install-${ifixName}"]

                }

            }

        }

    }

}
