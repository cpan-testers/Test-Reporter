# $Id: Makefile.PL,v 1.1.1.1 2002/08/09 03:39:30 afoxson Exp $
# $Revision: 1.1.1.1 $

use ExtUtils::MakeMaker;

WriteMakefile
(
	'NAME' => 'Test::Reporter',
	'PM' =>
	{
		'lib/Reporter.pm' => '$(INST_LIBDIR)/Reporter.pm',
	},
	'PREREQ_PM' =>
	{
		'Net::SMTP' => 0,
	},
	'VERSION_FROM' => 'lib/Reporter.pm',
	'dist' => { 'COMPRESS' => 'gzip --best' },
	(   
		$] >= 5.005 ?
		(   
			ABSTRACT_FROM => 'lib/Reporter.pm',
			AUTHOR => 'Adam J. Foxson <afoxson@pobox.com>',
		) : ()
	),
);
