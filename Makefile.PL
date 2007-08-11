# $Id: Makefile.PL,v 1.11 2003/02/25 08:45:04 afoxson Exp $
# $Revision: 1.11 $

# As configured, this distribution should be compatible, out-of-the box under
# all perl's since 5.00307. However, File::Spec is required, if you are
# running a perl < 5.005. File::Spec is a dependency of Errno, which is a
# dependency of File::Temp, which is a dependency of Test::Reporter.

use ExtUtils::MakeMaker;

WriteMakefile(
	'NAME' => 'Test::Reporter',
	'PM' => {
		'lib/Test/Reporter.pm' =>
			'$(INST_LIBDIR)/Reporter.pm',
		'lib/Test/Reporter/Mail/Util.pm' =>
			'$(INST_LIBDIR)/Reporter/Mail/Util.pm', # Version 1.58 bundled
		'lib/Test/Reporter/Date/Format.pm' =>
			'$(INST_LIBDIR)/Reporter/Date/Format.pm', # Version 2.22 bundled
		'lib/Test/Reporter/Time/Zone.pm' =>
			'$(INST_LIBDIR)/Reporter/Time/Zone.pm', # Version 2.22 bundled
	},
	'PREREQ_PM' => {
		'Net::SMTP' => 0,
		'File::Temp' => 0,
	},
	'VERSION_FROM' => 'lib/Test/Reporter.pm',
	'MAN3PODS' => {
		'lib/Test/Reporter.pod' => '$(INST_MAN3DIR)/Test::Reporter.3',
	},
	'dist' => {
		'COMPRESS' => 'gzip --best',
		'SUFFIX' => '.gz',
	},
	EXE_FILES => ['bin/cpantest'],
	(   
		$] >= 5.005 ?  (   
			ABSTRACT_FROM => 'lib/Test/Reporter.pod',
			AUTHOR => 'Adam J. Foxson <afoxson@pobox.com>',
		) : ()
	),
);
