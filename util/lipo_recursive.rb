#! /usr/bin/env ruby

require 'fileutils'

def show_usage()
puts <<USAGE_END
usage:
  #{$PROGRAM_NAME} \\
    [--header_condition <preproc_test_first>] \\
    [--install_subst <first> <second> <merged> [...]] \\
    <first_dir> <second_dir> <merged_dir>
  #{$PROGRAM_NAME} --help

Combine two architecture-specific installations into one combined
universal installation.  A number of strategies are employed, which
are needed to combine Qt builds, but this script can be used to
combine other artifacts too.

The script continues even if some individual files do not combine
properly - i.e. unknown files are not identical, etc.

For files that exist in both sources but cannot be combined properly:
  1. The file from <first> is copied to <merged> as a default
  2. The file from <second> is copied to <merged>_error to indicate the error

For files that exist in one source but not the other:
  1. Whichever file exists is copied to <merged>
  2. An empty file is created in <merged>_error to indicate the error

Strategies:
 * Mach objects (executable, dylib, dSYM) and static libraries:
   The files are combined with lipo(1).  The combined result is saved.
 * Symbolic links:
   The link targets must be identical (whether absolute or relative).
   The link is duplicated in the result.
 * C/C++ header files:
   The nonequal lines are toggled using the C preprocessor.  A test
   must be given with --header_condition.  For example:
      #{$PROGRAM_NAME} ... --header_condition '#ifndef __aarch64__'
   could produce:
      #ifndef __aarch64__
      #define QT_FEATURE_qt3d_simd_sse2 1
      #else
      #define QT_FEATURE_qt3d_simd_sse2 -1
      #endif
   (The conditions were generated by this script, the macro definitions
   were the lines from the headers.)
 * Files containing Qt configuration flags: *.prl, *.pri, *.cmake
   The files are checked to verify that only the expected differences are
   present, but no merge is performed - the file from the first architecture is
   used.
 * Files containing install directory names: *.pc, *.la
   The substitutions specified with --install_subst are applied.  The
   result should be identical for each source; if so, it is written to
   <merged>.

Arguments:
 * --header_condition <preproc_test_first>
   When merging header files, specify the preprocessor test used to test for the
   first architecture.  This will be followed by #else and #endif for the
   content for the second architecture.
   This can be omitted if the directories being merged do not contain headers.
 * --install_subst <first> <second> <merged>
   Specify a substitution to account for different install directories in
   library files.  In the first architecture, <first> is replaced with <merged>.
   In the second architecture, <second> is replaced with <merged>, and the
   result must be identical.
USAGE_END
end

$headerCondition = nil
$installSubstitutions = []
$firstSubstitutions = {}
$secondSubstitutions = {}

# Shift out N arguments, also checking that enough arguments were given
def takeArgs(count)
    if(count > ARGV.length)
        show_usage
        exit 1
    end
    ARGV.shift(count)
end
while !ARGV.empty?
    case ARGV.first
        when "--help"
            show_usage
            exit 0
        when "--header_condition"
            ARGV.shift
            $headerCondition = takeArgs(1)[0]
            # The condition can't contain %, this is included in a format string
            # passed to diff
            if $headerCondition.include? "%"
                puts "--header_condition value cannot include \"%\""
                exit 1
            end
        when "--install_subst"
            ARGV.shift
            # $installSubstitutions is an array of "3-tuples" (represented as
            # arrays, so grab the next 3 args and push them as a group
            subst = takeArgs(3)
            $installSubstitutions.push(subst)
            $firstSubstitutions[subst[0]] = subst[2]
            $secondSubstitutions[subst[1]] = subst[2]
        when "--"
            ARGV.shift
            break
        else
            # Check for an unknown option
            if ARGV.first.start_with?("--")
                show_usage
                exit 1
            end
            # Otherwise assume it's the directories
            break
    end
end

# Directory paths follow
positionalArgs = takeArgs(3)
$firstSource = positionalArgs[0]
$secondSource = positionalArgs[1]
$merged = positionalArgs[2]
$errors = "#{$merged}_errors"

puts "first installation: #{$firstSource}"
puts "second installation: #{$secondSource}"
puts "merged result: #{$merged}"
puts "header condition: #{$headerCondition}" if $headerCondition != nil
if !$installSubstitutions.empty?
    puts "install substitutions (#{$installSubstitutions.length})"
    $installSubstitutions.each do |i|
        puts "#{i[0]} / #{i[1]} -> #{i[2]}"
    end
end

# Execute a command and capture the output.  Deletes a single trailing line
# break if present.
# Ex: systemOutput("file", "/usr/bin/env")
#   -> returns the output of 'file' describing the env executable
def systemOutput(*args)
    output = ""
    # There's a version of IO.popen that returns a string without accepting a
    # block, but it sometimes gets stuck if a system call returns EAGAIN.  We
    # have to keep reading until the pipe is closed
    IO.popen(args) do |io|
        while !io.eof?
            output += io.read
        end
    end
    output.delete_suffix!("\n")
    output
end

# Determine the merge strategy to use for this directory entry.  If both
# corresponding entries have the same merge strategy, it will be used.  If they
# differ for some reason (mismatched types, etc.), we can't merge them.
def determineMergeType(path)
    # Check for a missing file
    return :missing unless File.exist?(path)

    # Check for symlinks - this must be first as the other detections would
    # look at the link target
    return :symlink if File.symlink?(path)

    # Check for a directory
    return :directory if File.directory?(path)

    # Check for our text file strategies based on extension
    entry = File.basename(path)
    return :text_prl if entry.end_with? ".prl"
    return :text_pri if entry.end_with? ".pri"
    return :text_cmake if entry.end_with? ".cmake"
    return :text_configh if entry.end_with?("config_p.h") || entry == "qconfig.h"
    return :text_la if entry.end_with? ".la"
    return :text_pc if entry.end_with? ".pc"

    # Check for something we can merge with lipo.  Even though the strategy is
    # the same, each of these has different types so we could detect a mismatch
    # between different types.
    fileType = systemOutput("file", "--brief", path)
    return :macho_exe if fileType.start_with? "Mach-O 64-bit executable "
    return :macho_lib if fileType.start_with? "Mach-O 64-bit dynamically linked shared library "
    return :macho_sym if fileType.start_with? "Mach-O 64-bit dSYM companion file "
    # Static libs can be lipo'd too - can return 'current ar archive' or
    # 'current ar archive random library', probably depends on whether ranlib
    # was run
    return :static_lib if fileType.start_with? "current ar archive"

    :other
end

# Merge a mismatched entry in first/second directories.  Used when the merge
# types do not match; this indicates an error.
$mismatches = []
def mergeMismatch(firstFile, secondFile, mergedFile, errorsFile)
    $mismatches.push(errorsFile)
    # Make sure the errors subdirectory exists; we only create these when a file
    # is actually placed.
    FileUtils.mkdir_p(File.dirname(errorsFile))
    # This is used to handle errors from some merge strategies, and there could
    # already be a file in the merge directory (if, say, lipo create the file
    # but encountered an error before returning).  This doesn't happen if either
    # source was a directory.
    FileUtils.rm_f(mergedFile)

    # One of the files must exist, or we wouldn't have found this entry at all.
    # If one of the files does _not_ exist, copy the other and create an empty
    # error file.
    if !File.exist?(firstFile)
        FileUtils.copy_entry(secondFile, mergedFile)
        FileUtils.touch(errorsFile)
    elsif !File.exist?(secondFile)
        FileUtils.copy_entry(firstFile, mergedFile)
        FileUtils.touch(errorsFile)
    else
        # Both exist, take the first arbitrarily and place the second in errors.
        FileUtils.copy_entry(firstFile, mergedFile)
        FileUtils.copy_entry(secondFile, errorsFile)
    end
end

# Merge two symlinks
def mergeSymlinks(firstFile, secondFile, mergedFile, errorsFile)
    # Check if the link targets match
    if File.readlink(firstFile) == File.readlink(secondFile)
        # Match; just copy one
        FileUtils.copy_entry(firstFile, mergedFile)
    else
        mergeMismatch(firstFile, secondFile, mergedFile, errorsFile)
    end
end

# Merge anything that can be combined with lipo (Mach objects or static libs)
def mergeLipo(firstFile, secondFile, mergedFile, errorsFile)
    if !system("lipo", "-create", firstFile, secondFile, "-output", mergedFile)
        mergeMismatch(firstFile, secondFile, mergedFile, errorsFile)
    end
end

def installSubstitute(lineRegex, substitutions, fileText)
    fileText.gsub(lineRegex) do |match|
        substitutions.each { |k, v| match = match.gsub(k, v) }
        match
    end
end

def mergeInstallText(regex, firstSubst, secondSubst, firstFile, secondFile,
    mergedFile, errorsFile, sortLines: false)
    # Read each file and apply the install substitutions.  The result should be
    # identical.
    firstText = File.read(firstFile)
    secondText = File.read(secondFile)
    firstText = installSubstitute(regex, firstSubst, firstText)
    secondText = installSubstitute(regex, secondSubst, secondText)

    return firstText if firstText == secondText
    # This is rare, but occasionally some files generate lines in slightly
    # different orders in the different arch builds (in such a way that is not
    # a significant difference).  Setting sortLines to true tolerates different
    # line ordering.  Use this with caution!
    return firstText if sortLines && firstText.lines.sort == secondText.lines.sort
    nil
end

def mergeInstallFiles(regex, firstSubst, secondSubst, firstFile, secondFile,
    mergedFile, errorsFile)
    mergedText = mergeInstallText(regex, firstSubst, secondSubst, firstFile,
        secondFile, mergedFile, errorsFile)
    if mergedText != nil
        File.write(mergedFile, mergedText)
    else
        mergeMismatch(firstFile, secondFile, mergedFile, errorsFile)
    end
end

PriPrlSubst = {
    # These CPU feature flags commonly appear in .prl files.  They also appear
    # in qmodules.pri.  These are carefully ordered as many are prefixes of
    # others.
    " sse2" => "",
    " aesni" => "",
    " ssse3" => "",
    " sse3" => "",
    " sse4_1" => "",
    " sse4_2" => "",
    " avx512f" => "",
    " avx512bw" => "",
    " avx512cd" => "",
    " avx512dq" => "",
    " avx512er" => "",
    " avx512ifma" => "",
    " avx512pf" => "",
    " avx512vbmi" => "",
    " avx512vl" => "",
    " avx512common" => "",
    " avx512core" => "",
    " avx2" => "",
    " avx" => "",
    " f16c" => "",
    " rdrnd" => "",
    " rdseed" => "",
    " shani" => "",
    " x86SimdAlways" => "",
    " simd" => "",
    " arch_haswell" => "",
    " cx16" => "",
    " mmx" => "",
    " sse4.1" => "",
    " sse" => "",
    " neon" => "",
    " crc32" => "",
    # These architecture names appear in qconfig.pri
    "x86_64" => "universal",
    "arm64" => "universal",
    # These configuration features appear in specific pri files.
    " qt3d-simd-sse2" => "",
    " qml-jit" => ""
}

# .prl files contain the Qt configuration flags, which includes a bunch of
# CPU-specific features (sse2, rdrand, neon, etc.).  Just delete the flags.
# We don't use these in PIA either (we don't use qmake), but this also seems
# to only affect products that test these features specifically.
#
# Unlike .pri/.cmake, the disabled features are not listed, so we probably could
# safely delete the flags and use that result - but since we're not totally
# merging the pri files (see below), take the x86_64 file here too.
def mergePrl(firstFile, secondFile, mergedFile, errorsFile)
    if mergeInstallText(/^QMAKE_PRL_CONFIG = .*$/, PriPrlSubst, PriPrlSubst,
        firstFile, secondFile, mergedFile, errorsFile)
        FileUtils.copy_entry(firstFile, mergedFile)
    else
        mergeMismatch(firstFile, secondFile, mergedFile, errorsFile)
    end
end

# Both .pri and .cmake files contain lists of enabled/disabled features.  In our
# macOS builds of Qt, two features differ between x86_64 and arm64:
#  - Qt53DCore - qt3d-simd-sse2
#  - Qt5Qml - qml-jit
#
# In both cases the feature is enabled on x86_64, but disabled on arm64.  (SSE2
# is obviously x86_64-specific.  QML JIT is not implemented for arm64 on macOS -
# this is still the case in 6.2, possibly because Apple doesn't allow the
# entitlement needed for JIT on arm64 in the App Store.)
#
# Additionally, qconfig.pri specifically mentions the target architecture
# (QT_ARCH, QT_BUILDABI).  qmodule.pri also mentions target architecture,
# per-arch features, and more copies of config flags.
#
# The feature flags probably don't matter unless the product specifically wants
# to test for those features at build time; and both of these features are
# probably unlikely to be tested.
#
# The other arch references probably would matter to qmake, so the resulting
# build probably will not work with qmake.  We're just taking the x86_64 file
# arbitrarily; in theory this would probably work for an x86_64 build with
# qmake, although that's untested.  qmake in 5.15.2 doesn't really support
# universal builds, so there's no effort made to describe the multi-arch
# configuration.
#
# In both cases, we do substitutions to verify that the difference really is
# what we expect, but we then use the x86_64 file
def mergePri(firstFile, secondFile, mergedFile, errorsFile)
    # For most files we just care about QT.<module>.(en|dis)abled_features
    # qconfig.pri has QT_ARCH, QT_BUILDABI
    # qmodule.pri has QMAKE_APPLE_DEVICE_ARCHS, CONFIG
    #
    # Strangely, in qmodule.pri, the order of 'QT_BUILD_PARTS += ...' and
    # 'CONFIG += ...' seems to vary between x86_64 and arm64.  Tolerate this by
    # enabling sortLines in mergeInstallText().  This is crude and could
    # tolerate differences that are actually significant, but it seems fine for
    # this file.
    if mergeInstallText(/^ *(QT\.[a-zA-Z0-9_]+\.(en|dis)abled_features|QT_ARCH|QT_BUILDABI|QMAKE_APPLE_DEVICE_ARCHS|QT_CPU_FEATURES.[a-zA-Z0-9_]+|CONFIG)[ =+].*$/,
        PriPrlSubst, PriPrlSubst, firstFile, secondFile, mergedFile, errorsFile,
        sortLines: File.basename(firstFile) == "qmodule.pri")
        FileUtils.copy_entry(firstFile, mergedFile)
    else
        mergeMismatch(firstFile, secondFile, mergedFile, errorsFile)
    end
end
def mergeCmake(firstFile, secondFile, mergedFile, errorsFile)
    cmakeSubst = {
        ";qt3d-simd-sse2" => "",
        "qt3d-simd-sse2" => "",
        ";qml-jit" => "",
        "qml-jit" => ""
    }
    # The line regex is not very specific, the cmake property name is on a
    # preceding line :-/  The identifiers are pretty specific though, and we
    # don't actually use the merge result, we're just verifying that no other
    # features differ
    if mergeInstallText(/^ +[^()]+\)$/,
        cmakeSubst, cmakeSubst, firstFile, secondFile, mergedFile, errorsFile)
        FileUtils.copy_entry(secondFile, mergedFile)
    else
        mergeMismatch(firstFile, secondFile, mergedFile, errorsFile)
    end
end

# Merge header files (toggled using specified test)
$warnNeedHeaderCondition = false
def mergeConfigh(firstFile, secondFile, mergedFile, errorsFile)
    if $headerCondition == nil
        # No header condition was given, we can't merge these.  Warn at the end.
        $warnNeedHeaderCondition = true
        return mergeMismatch(firstFile, secondFile, mergedFile, errorsFile)
    end
    # 'diff' can do this for us - it can finds the changed lines between the
    # two files, we just need to tell it to delimit with #if/#else/#endif

    # Line ending in diff's format syntax
    endl = "%c'\\12'"
    # 'if' marker (specified with command line paremter, could be #if or #ifdef
    # This assumes that $headerCondition does not contain '%', which indicates
    # format specifications to diff
    ifMk = "#{$headerCondition}#{endl}"
    # 'else' marker
    elseMk = "#else#{endl}"
    # 'endif' marker
    endifMk = "#endif#{endl}"

    mergedText = systemOutput(
        "diff",
        # Common lines - output verbatim
        "--unchanged-group-format=%=",
        # Old-only lines - output with only the test and #endif
        "--old-group-format=#{ifMk}%<#{endifMk}",
        # New-only lines - output with test, else, and endif.  '#else' just
        # inverts the test essentially
        "--new-group-format=#{ifMk}#{elseMk}%>#{endifMk}",
        # Changed lines - use test, else, and endif
        "--changed-group-format=#{ifMk}%<#{elseMk}%>#{endifMk}",
        firstFile, secondFile)
    File.write(mergedFile, mergedText)
end

# Merge .la files (libtool library files, contains install directory)
def mergeLa(firstFile, secondFile, mergedFile, errorsFile)
    mergeInstallText(/^(dependency_libs|libdir)=.*$/, $firstSubstitutions,
        $secondSubstitutions, firstFile, secondFile, mergedFile, errorsFile)
end

# Merge .pc files (packageconfig files, contains install directory)
def mergePc(firstFile, secondFile, mergedFile, errorsFile)
    mergeInstallText(/^(prefix=|Libs.private: ).*$/, $firstSubstitutions,
        $secondSubstitutions, firstFile, secondFile, mergedFile, errorsFile)
end

def mergeDirEntry(first, second, merged, errors, entry)
    firstFile = File.join(first, entry)
    secondFile = File.join(second, entry)
    mergedFile = File.join(merged, entry)
    errorsFile = File.join(errors, entry)

    mergeType = determineMergeType(firstFile)
    # If the two entries don't have the same merge strategy, we can't merge
    # them.  If either was missing, we'll do this - they can't both be
    # missing or we would not have found the entry at all.
    if determineMergeType(secondFile) != mergeType
        return mergeMismatch(firstFile, secondFile, mergedFile, errorsFile)
    end

    # Apply the appropriate merge strategy
    return mergeSymlinks(firstFile, secondFile, mergedFile, errorsFile) if mergeType == :symlink
    # Recurse for subdirectories
    return mergeDirs(firstFile, secondFile, mergedFile, errorsFile) if mergeType == :directory
    # All mach-o types and static libraries use the same implementation with
    # lipo, but the exact types must match
    if [:macho_exe, :macho_lib, :macho_sym, :static_lib].include? mergeType
        return mergeLipo(firstFile, secondFile, mergedFile, errorsFile)
    end

    # For all other types (text-based merge strategies and 'other'), if the
    # files are identical, just copy one, no need to apply a strategy
    if system("cmp", "--silent", firstFile, secondFile)
        return FileUtils.copy_entry(firstFile, mergedFile)
    end

    # The files are not identical, apply text merge strategies.
    case mergeType
    when :text_prl
        mergePrl(firstFile, secondFile, mergedFile, errorsFile)
    when :text_pri
        mergePri(firstFile, secondFile, mergedFile, errorsFile)
    when :text_cmake
        mergeCmake(firstFile, secondFile, mergedFile, errorsFile)
    when :text_configh
        mergeConfigh(firstFile, secondFile, mergedFile, errorsFile)
    when :text_la
        mergeLa(firstFile, secondFile, mergedFile, errorsFile)
    when :text_pc
        mergePc(firstFile, secondFile, mergedFile, errorsFile)
    else
        # We don't have a merge strategy, and these files differ.
        mergeMismatch(firstFile, secondFile, mergedFile, errorsFile)
    end
end

def mergeDirs(first, second, merged, errors)
    puts "entering: #{first}"
    Dir.mkdir(merged)
    # Get the unique combined entries from both first and second
    entries = Dir.glob("*", File::FNM_DOTMATCH, base: first)
    entries += Dir.glob("*", File::FNM_DOTMATCH, base: second)
    entries.sort!
    entries.uniq!
    entries.reject! { |e| ['.', '..', '.DS_Store'].include? e }

    entries.each { |entry| mergeDirEntry(first, second, merged, errors, entry) }
end

# Delete the merged and errors directories if they exist
FileUtils.rm_rf($merged)
FileUtils.rm_rf($errors)
# Kick off the merge from the directories specified
mergeDirs($firstSource, $secondSource, $merged, $errors)

if $warnNeedHeaderCondition
    puts "WARNING: encountered differing header files, but --header_condition was not given - cannot merge"
end
puts "merge complete"
if !$mismatches.empty?
    puts "WARNING: files could not be merged:"
    $mismatches.each { |m| puts "  #{m}" }
end
