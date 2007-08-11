# $Id: Makefile.PL,v 1.12 2003/03/05 05:41:17 afoxson Exp $
# $Revision: 1.12 $

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
		'File::Spec' => 0,
	},
	'VERSION_FROM' => 'lib/Test/Reporter.pm',
	'MAN3PODS' => {
		'lib/Test/Reporter.pod' => '$(INST_MAN3DIR)/Test::Reporter.$(MAN3EXT)',
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
	'clean' => {
		'FILES' => '*.rpt',
	},
);
