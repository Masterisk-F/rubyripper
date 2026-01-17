# RubyRipperRemix (RRR)

*A secure audiodisc ripper for Linux*

This project is a fork of [Rubyripper](https://github.com/bleskodev/rubyripper).

## Key Changes in this Fork

*   Migration to libcdio-paranoia: Replaced `cdparanoia` with the more actively maintained `libcdio-paranoia` (cd-paranoia).
*   [AccurateRip](https://accuraterip.com/) support for verifying ripped data.
*   Bug Fixes & Improvements:
    *   Removed legacy cdparanoia `-Z` workaround for better performance.
    *   Added CATALOG number (UPC/EAN) support in cuesheets.
    *   Fixed various issues with artist name handling (compilations, single album artist).
    *   Other minor fixes and improvements.

---

*The content below is from the original Rubyripper documentation.*

* [Historical note](#Historical-note)
* [Introduction](#Introduction)
* [Secure rip method](#Secure-rip-method)
* [How to install](#How-to-install)
  * [MacOS Support](#MacOS-support)
* [FAQ](#FAQ)
* [Running all tests](#Running-all-tests)


# Historical note<a name="Historical-note"></a>

This is an unofficial fork of the original Rubyripper from [Google code](https://code.google.com/archive/p/rubyripper/).
The code was abandoned in 2014 by the original author. I was (and still am)
a user, and the latest released version (0.6.2) stopped working for me as I
followed the OS upgrades. The head branch (0.7.0a1) was left by the original
author in the alpha state. I have forked the code, fixed the problems I was
aware of and added some small features. 99% of the code is still from the
original author (boukewoudstra, kudos to him).
In the current state, the code works for me. I'm fixing reported bugs when
I have time and energy.


# Introduction<a name="Introduction"></a>

Rubyripper aims to deliver high quality rips from audio cd's to your computer
drive. It tries to do so by ripping the same track with cdparanoia multiple
times and then comparing the results. It currently has a gtk3 and a command-
line interface.

Some of it's main features:
* graphical (gtk3) and command line interface
* a [secure rip method](#Secure-rip-method)
* editable gnudb and musicbrainz tag fetching
* flac, vorbis, mp3, wav support
* any other codec by passing the command
* multiple codec encoding in one run
* offset support
* pass parameters to cdparanoia
* playlist creation
* logfile with analysis of corrected and impossible to correct positions
* MD5sum for each track included in the logfile


# Secure rip method<a name="Secure-rip-method"></a>

The underlying philosophy is that errors are random and therefore will differ
with each trial. Since the files don't always match directly proves that at
least part of this is true. However, it might be that some read errors are not
random and will happen exactly the same with multiple trials. In this case an
error would slip through unnoticed.

A completely secure rip can never be guaranteed, neither by Exact Audio Copy
(which inspired Rubyripper), nor by any other ripper. Factors like the
quality of the audio-cd and the quality of the cdrom drive are very important
as well. Despite these problems Rubyripper tries to do it's very best.

The user can set a number of 'A' matches for each chunk of 1000 bytes. Each
chunk represents about 0,006 seconds. If, after ripping the track 'A' times,
there are chunks that don't match 'A' times, another trial is launched. This
time however, the mismatched chunks must match 'B' times, which can be equal,
but not smaller to 'A' times.

When Rubyripper has finished the ripping process, a suspicious positions
analysis will be added to the logfile. For each second in the file it will
be shown how much mismatched chunks there were originally. And at which trial
these were corrected or not at all.

It's possible to set a limit to the number of times a track is ripped. For some
tracks it seems impossible to ever get a correct rip. The amount of errors left
are usually very small though. It's not likely one actually will be able to
hear this.


# How to install<a name="How-to-install"></a>

Dependencies:
* cdparanoia
* ruby 1.9 and higher
* ruby-rexml (gem)

Suggested:
* ruby-gettext (for translations)
* ruby-gtk3 (for gtk3 gui)
* cd-discid or discid (for proper gnudb support)
* eject or diskutil for MacOS (for eject support)
* flac, oggenc, lame, neroAacEnc, wavpack (if the codec is wanted)
* wavegain, vorbisgain, mp3gain, aacgain, wvgain (for replaygain support)
* normalize (for normalize support)
* sox (for de-emphasize audio tracks)
* cdrdao (for advanced toc analysis)

Run from directory:
<pre>
./bin/rubyripper_gtk3 or 
./bin/rubyripper_cli
</pre>

To install:
<pre>
./configure --enable-lang-all --enable-gtk3 --enable-cli --prefix=/usr or
./configure --enable-lang=de,hu --enable-gtk3 --enable-cli --prefix=/usr
make install
</pre>

The executables will be named `rrip_cli` and `rrip_gui`

To uninstall: `make uninstall`
To cleanup: `make clean`


## MacOS support<a name="MacOS-support"></a>

The CLI now works in MacOS. However, if your cdparanoia version
doesn't support the -d switch (to set the device), only the default
drive can be used. Rubyripper doesn't do this for you, so if you got
weird results with gnudb fetching, use your other cdrom drive.

A cdparanoia port for MacOS that supports the -d switch [can be found here](http://sourceforge.net/project/showfiles.php?group_id=158413)

For MacOS on x86 systems cd-discid is not working (ppc does), [but discid is](http://discid.sourceforge.net/)
You can also test the fallback code for creating the discid ourselves,
but it may not work on audio-cd's with a data track.


# FAQ<a name="FAQ"></a>

**Q :** Why does the last track go slower than the rest?

**A :** Chances are that you've supplied an offset different than 0 and supplied the
option -Z to cdparanoia. A cdparanoia bug prevents finishing ripping the last
track if -Z is supplied, so it's automatically removed for the last track.

**Q :** Will Rubyripper work on any platform other than linux?

**A :** If the same dependencies are available on these platforms, then things will
probably just work fine. If some of the dependencies are missing, but you do
know one other utility which does just about the same, please report a
feature request at the GitHub bugtracker.

**Q :** How do I report a bug / request a missing feature?

**A :** Go to the [Github repository](https://github.com/bleskodev/rubyripper)!

**Q :** How do I get the very latest code (I don't care how many bugs there are)?

**A :** Using git. See the wiki for instructions.

**Q :** My buttons don't react and give the following error in a terminal:
warning: GRClosure invoking callback: already destroyed Callback error

**A :** Upgrade your ruby gtk bindings to a >=0.16.* version.

**Q :** How can I help translate rubyripper to my language?

**A :** See the wiki for instructions


# Running all tests<a name="Running-all-tests"></a>
All feature tests can be run with `cucumber`. Of course you should have
installed cucumber. This can be done with `gem install cucumber`. The
`gem` command should be installed by default in any Ruby installation.
The feature tests can be found in the features folder.

All unit tests can be run with `rspec`. Of course you should have
installed rspec. This can be done with `gem install rspec`. The
`gem` command should be installed by default in any Ruby installation.
The rspec tests can be found in the spec folder.
