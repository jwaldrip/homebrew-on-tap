# homebrew-core's git formula (Formula/g/git.rb at Homebrew/homebrew-core
# 1117d6b85477, 2.56.0_1) built from source with one upstream patch:
#
#   [PATCH v2] regexec: work around macOS TRE leak on invalid UTF-8
#   Chungmin Lee, 2026-07-28, base v2.55.0 (e9019fcafe00)
#   https://ratatoskr.run/git/2026/07/17327678
#
# macOS's TRE regexec() leaks a buffer on every call that meets invalid UTF-8
# in a UTF-8 locale, so `git grep` over binary files grows by gigabytes in
# under a second. The patch searches the valid runs between invalid bytes
# instead of handing invalid bytes to regexec().
#
# Differences from core: no bottle, no head spec, no revision, the patch.
# Retire this formula once a git release that core ships contains
# compat/darwin/regexec.c:
#   brew uninstall jwaldrip/on-tap/git && brew install git
class Git < Formula
  desc "Distributed revision control system"
  homepage "https://git-scm.com"
  url "https://mirrors.edge.kernel.org/pub/software/scm/git/git-2.56.0.tar.xz"
  sha256 "26c56c296b38c0695b26fa95f475f1d01704d2d38e73465ca30b0b2f5dc789d3"
  license all_of: [
    "GPL-2.0-only",
    "GPL-2.0-or-later",  # imap-send.c; trace.c; ...
    "LGPL-2.1-or-later", # xdiff/
    "BSD-3-Clause",      # xdiff/xhistogram.c; reftable/
    "MIT",               # khash.h; sha1dc/
  ]
  compatibility_version 1

  livecheck do
    url "https://mirrors.edge.kernel.org/pub/software/scm/git/"
    regex(/href=.*?git[._-]v?(\d+(?:\.\d+)+)\.t/i)
  end

  depends_on "gettext" => :build
  depends_on "pkgconf" => :build
  depends_on "pcre2"

  uses_from_macos "curl"
  uses_from_macos "expat"

  # Don't try to add a libiconv dependency without reading this PR first:
  # https://github.com/Homebrew/homebrew-core/pull/258461

  on_macos do
    depends_on "gettext"
  end

  on_linux do
    depends_on "openssl@4" # for git-imap-send (GPL-2.0-or-later), uses CommonCrypto on macOS
    depends_on "zlib-ng-compat"
  end

  resource "Authen::SASL" do
    url "https://cpan.metacpan.org/authors/id/E/EH/EHUELS/Authen-SASL-2.2000.tar.gz"
    sha256 "8cdf5a7f185448b614471675dae5b26f8c6e330b62264c3ff5d91172d6889b99"
  end

  resource "html" do
    url "https://mirrors.edge.kernel.org/pub/software/scm/git/git-htmldocs-2.56.0.tar.xz"
    sha256 "c20a04cffce877e29ec532c5453f3fd2ce1f3daaf7f3b65d1f2fa73e95986d11"

    livecheck do
      formula :parent
    end
  end

  resource "man" do
    url "https://mirrors.edge.kernel.org/pub/software/scm/git/git-manpages-2.56.0.tar.xz"
    sha256 "1f62a7fabaa36a0469c4d51fe247d12e7e246b890d2b8b49aec91df610f417c7"

    livecheck do
      formula :parent
    end
  end

  resource "Net::SMTP::SSL" do
    url "https://cpan.metacpan.org/authors/id/R/RJ/RJBS/Net-SMTP-SSL-1.04.tar.gz"
    sha256 "7b29c45add19d3d5084b751f7ba89a8e40479a446ce21cfd9cc741e558332a00"
  end

  # The upstream patch described at the top of this file, verbatim.
  patch :DATA

  allow_network_access! :test

  def install
    odie "html resource needs to be updated" if build.stable? && version != resource("html").version
    odie "man resource needs to be updated" if build.stable? && version != resource("man").version

    # If these things are installed, tell Git build system not to use them
    ENV["NO_FINK"] = "1"
    ENV["NO_DARWIN_PORTS"] = "1"
    ENV["PYTHON_PATH"] = which("python3")
    ENV["PERL_PATH"] = which("perl")
    ENV["USE_LIBPCRE2"] = "1"
    ENV["INSTALL_SYMLINKS"] = "1"
    ENV["LIBPCREDIR"] = formula_opt_prefix("pcre2")
    ENV["V"] = "1" # build verbosely

    perl_version = Utils.safe_popen_read("perl", "--version")[/v(\d+\.\d+)(?:\.\d+)?/, 1]

    if OS.mac?
      ENV["PERLLIB_EXTRA"] = %W[
        #{MacOS.active_developer_dir}
        /Library/Developer/CommandLineTools
        /Applications/Xcode.app/Contents/Developer
      ].uniq.map do |p|
        "#{p}/Library/Perl/#{perl_version}/darwin-thread-multi-2level"
      end.join(":")
    end

    # The git-gui and gitk tools are installed by a separate formula (git-gui)
    # to avoid a dependency on tcl-tk and to avoid using the broken system
    # tcl-tk (see https://github.com/Homebrew/homebrew-core/issues/36390)
    # This is done by setting the NO_TCLTK make variable.
    args = %W[
      prefix=#{prefix}
      sysconfdir=#{etc}
      CC=#{ENV.cc}
      CFLAGS=#{ENV.cflags}
      LDFLAGS=#{ENV.ldflags}
      NO_TCLTK=1
      NO_RUST=1
    ]

    args += if OS.mac?
      %w[NO_OPENSSL=1 APPLE_COMMON_CRYPTO=1]
    else
      openssl_prefix = formula_opt_prefix("openssl@4")

      %W[NO_APPLE_COMMON_CRYPTO=1 OPENSSLDIR=#{openssl_prefix}]
    end

    # Make sure `git` looks in `opt_prefix` instead of the Cellar.
    # Otherwise, Cellar references propagate to generated plists from `git maintenance`.
    inreplace "Makefile", /(-DFALLBACK_RUNTIME_PREFIX=")[^"]+/, "\\1#{opt_prefix}"

    system "make", "install", *args

    git_core = libexec/"git-core"
    rm git_core/"git-svn"

    # Install the macOS keychain credential helper
    if OS.mac?
      cd "contrib/credential/osxkeychain" do
        system "make", *args
        git_core.install "git-credential-osxkeychain"
        system "make", "clean"
      end
    end

    # Generate diff-highlight perl script executable
    cd "contrib/diff-highlight" do
      system "make"
    end

    # Install the netrc credential helper
    cd "contrib/credential/netrc" do
      system "make", "test"
      git_core.install "git-credential-netrc"
    end

    # Install git-subtree
    cd "contrib/subtree" do
      system "make", "CC=#{ENV.cc}",
                     "CFLAGS=#{ENV.cflags}",
                     "LDFLAGS=#{ENV.ldflags}"
      git_core.install "git-subtree"
    end

    # Install git-jump
    cd "contrib/git-jump" do
      git_core.install "git-jump"
    end

    # install the completion script first because it is inside "contrib"
    bash_completion.install "contrib/completion/git-completion.bash"
    bash_completion.install "contrib/completion/git-prompt.sh"
    zsh_completion.install "contrib/completion/git-completion.zsh" => "_git"
    cp "#{bash_completion}/git-completion.bash", zsh_completion
    cp "#{bash_completion}/git-prompt.sh", zsh_completion

    (share/"git-core").install "contrib"

    # We could build the manpages ourselves, but the build process depends
    # on many other packages, and is somewhat crazy, this way is easier.
    man.install resource("man")
    (share/"doc/git-doc").install resource("html")

    # Make html docs world-readable
    chmod 0644, Dir["#{share}/doc/git-doc/**/*.{html,txt}"]
    chmod 0755, Dir["#{share}/doc/git-doc/{RelNotes,howto,technical}"]

    # git-send-email needs Net::SMTP::SSL or Net::SMTP >= 2.34 and Authen::SASL
    resource("Net::SMTP::SSL").stage do
      (share/"perl5").install "lib/Net"
    end

    resource("Authen::SASL").stage do
      (share/"perl5").install "lib/Authen"
    end

    # This is only created when building against system Perl, but it isn't
    # purged by Homebrew's post-install cleaner because that doesn't check
    # "Library" directories. It is however pointless to keep around as it
    # only contains the perllocal.pod installation file.
    perl_dir = prefix/"Library/Perl"
    rm_r perl_dir if perl_dir.exist?

    # Set the macOS keychain credential helper by default
    # (as Apple's CLT's git also does this).
    if OS.mac?
      (buildpath/"gitconfig").write <<~EOS
        [credential]
        \thelper = osxkeychain
      EOS
      etc.install "gitconfig"
    end
  end

  def caveats
    <<~EOS
      The Tcl/Tk GUIs (e.g. gitk, git-gui) are now in the `git-gui` formula.
      Subversion interoperability (git-svn) is now in the `git-svn` formula.
    EOS
  end

  test do
    system bin/"git", "init"
    %w[haunted house].each { |f| touch testpath/f }
    system bin/"git", "add", "haunted", "house"
    system bin/"git", "config", "user.name", "'A U Thor'"
    system bin/"git", "config", "user.email", "author@example.com"
    system bin/"git", "commit", "-a", "-m", "Initial Commit"
    assert_equal "haunted\nhouse", shell_output("#{bin}/git ls-files").strip

    # Check that our `inreplace` for the `Makefile` does not break.
    # If this assertion fails, please fix the `inreplace` instead of removing this test.
    # The failure of this test means that `git` will generate broken launchctl plist files.
    refute_match HOMEBREW_CELLAR.to_s, shell_output("#{bin}/git --exec-path")

    return unless OS.mac?

    # The patch keeps invalid UTF-8 out of macOS's TRE regexec(). Unpatched,
    # git misses "world" after the invalid byte and the -i grep over binfile
    # peaks near 2.2 GB; patched, it finds the line and stays under 10 MB.
    with_env(LC_ALL: "en_US.UTF-8") do
      (testpath/"invalid-utf8").binwrite("before\xE6world\n")
      (testpath/"binfile").binwrite("#{"\xFF" * 16}\n" * 300_000)
      system bin/"git", "add", "invalid-utf8", "binfile"
      system bin/"git", "commit", "-m", "Invalid UTF-8"

      assert_equal "before\xE6world\n".b,
                   shell_output("#{bin}/git grep -h 'worl[d]' invalid-utf8").b

      pattern = %w[aa bb cc dd ee ff gg hh ii jj kk ll mm nn oo pp qq rr ss tt].join("|")
      usage = shell_output("/usr/bin/time -l #{bin}/git grep -i -E '#{pattern}' binfile 2>&1", 1)
      footprint = usage[/(\d+)\s+peak memory footprint/, 1].to_i
      assert_operator footprint, :>, 0
      assert_operator footprint, :<, 256 * 1024 * 1024
    end

    # Check Net::SMTP or Net::SMTP::SSL works for git-send-email
    %w[foo bar].each { |f| touch testpath/f }
    system bin/"git", "add", "foo", "bar"
    system bin/"git", "commit", "-a", "-m", "Second Commit"
    assert_match "Authentication Required", pipe_output(
      "#{bin}/git send-email --from=test@example.com --to=dev@null.com " \
      "--smtp-server=smtp.gmail.com --smtp-server-port=587 " \
      "--smtp-encryption=tls --confirm=never HEAD^ 2>&1",
    )
  end
end

__END__
diff --git a/Makefile b/Makefile
index 1cec251..81075c3 100644
--- a/Makefile
+++ b/Makefile
@@ -2264,6 +2264,10 @@ ifdef USE_ENHANCED_BASIC_REGULAR_EXPRESSIONS
 	COMPAT_CFLAGS += -DUSE_ENHANCED_BASIC_REGULAR_EXPRESSIONS
 	COMPAT_OBJS += compat/regcomp_enhanced.o
 endif
+ifdef DARWIN_REGEXEC
+	COMPAT_OBJS += compat/darwin/regexec.o
+	BASIC_CFLAGS += -DDARWIN_REGEXEC
+endif
 endif
 ifdef NATIVE_CRLF
 	BASIC_CFLAGS += -DNATIVE_CRLF
diff --git a/compat/darwin.h b/compat/darwin.h
new file mode 100644
index 0000000..6fbdc34
--- /dev/null
+++ b/compat/darwin.h
@@ -0,0 +1,8 @@
+#ifndef COMPAT_DARWIN_H
+#define COMPAT_DARWIN_H
+
+int darwin_regexec_buf(const regex_t *preg, const char *buf, size_t size,
+		       size_t nmatch, regmatch_t pmatch[], int eflags);
+#define regexec_buf darwin_regexec_buf
+
+#endif
diff --git a/compat/darwin/regexec.c b/compat/darwin/regexec.c
new file mode 100644
index 0000000..13fb7d5
--- /dev/null
+++ b/compat/darwin/regexec.c
@@ -0,0 +1,91 @@
+#include "git-compat-util.h"
+
+#include <wchar.h>
+
+/*
+ * Darwin's TRE regex engine leaks an internal buffer when it encounters an
+ * invalid multibyte sequence.  Since the leak has already happened when
+ * regexec() reports REG_ILLSEQ, keep invalid bytes out of regexec() by
+ * searching each valid segment separately.
+ */
+
+/*
+ * Search buf[start, end), where size is the full size of buf.  REG_STARTEND
+ * keeps match offsets relative to buf.  Do not let an internal segment create
+ * a false beginning or end of line.
+ */
+static int regexec_segment(const regex_t *preg, const char *buf,
+			   size_t size, size_t start, size_t end,
+			   size_t nmatch, regmatch_t pmatch[], int eflags)
+{
+	eflags |= REG_STARTEND;
+	if (start > 0)
+		eflags |= REG_NOTBOL;
+	if (end < size)
+		eflags |= REG_NOTEOL;
+	pmatch[0].rm_so = start;
+	pmatch[0].rm_eo = end;
+	return regexec(preg, buf, nmatch, pmatch, eflags);
+}
+
+int darwin_regexec_buf(const regex_t *preg, const char *buf, size_t size,
+		       size_t nmatch, regmatch_t pmatch[], int eflags)
+{
+	size_t seg_start = 0, i = 0;
+	mbstate_t mbs;
+
+	assert(nmatch > 0 && pmatch);
+
+	/*
+	 * A single-byte locale cannot contain an invalid multibyte sequence,
+	 * so use regexec() directly.
+	 */
+	if (MB_CUR_MAX == 1) {
+		pmatch[0].rm_so = 0;
+		pmatch[0].rm_eo = size;
+		return regexec(preg, buf, nmatch, pmatch, eflags | REG_STARTEND);
+	}
+
+	memset(&mbs, 0, sizeof(mbs));
+	while (i < size) {
+		unsigned char c = (unsigned char)buf[i];
+		size_t n;
+
+		if (c < 0x80) {
+			i++;
+			continue;
+		}
+
+		n = mbrtowc(NULL, buf + i, size - i, &mbs);
+		if (!n)
+			n = 1;
+		if (n != (size_t)-1 && n != (size_t)-2) {
+			i += n;
+			continue;
+		}
+
+		/*
+		 * -1 denotes an encoding error; -2 denotes an incomplete
+		 * trailing sequence.  In either case, buf[i] cannot begin a
+		 * complete valid character within this buffer.  Search an
+		 * empty initial segment to preserve zero-width matches at the
+		 * true beginning.
+		 */
+		if (i > seg_start || i == 0) {
+			int ret = regexec_segment(preg, buf, size, seg_start, i,
+						  nmatch, pmatch, eflags);
+			if (ret != REG_NOMATCH)
+				return ret;
+		}
+		i++;
+		seg_start = i;
+		memset(&mbs, 0, sizeof(mbs));
+	}
+
+	/*
+	 * Search the final segment even when it is empty, so an empty buffer
+	 * or a buffer ending in invalid bytes still has its true end.
+	 */
+	return regexec_segment(preg, buf, size, seg_start, size,
+			       nmatch, pmatch, eflags);
+}
diff --git a/config.mak.uname b/config.mak.uname
index 9ebd240..4660ff3 100644
--- a/config.mak.uname
+++ b/config.mak.uname
@@ -154,6 +154,7 @@ ifeq ($(uname_S),Darwin)
 	HAVE_DEV_TTY = YesPlease
 	COMPAT_OBJS += compat/precompose_utf8.o
 	BASIC_CFLAGS += -DPRECOMPOSE_UNICODE
+	DARWIN_REGEXEC = YesPlease
 	BASIC_CFLAGS += -DPROTECT_HFS_DEFAULT=1
 	HAVE_BSD_SYSCTL = YesPlease
 	FREAD_READS_DIRECTORIES = UnfortunatelyYes
diff --git a/contrib/buildsystems/CMakeLists.txt b/contrib/buildsystems/CMakeLists.txt
index a57c4b4..83e8b71 100644
--- a/contrib/buildsystems/CMakeLists.txt
+++ b/contrib/buildsystems/CMakeLists.txt
@@ -519,6 +519,9 @@ if(NOT HAVE_REGEX)
 	include_directories(${CMAKE_SOURCE_DIR}/compat/regex)
 	list(APPEND compat_SOURCES compat/regex/regex.c )
 	add_compile_definitions(NO_REGEX NO_MBSUPPORT GAWK)
+elseif(APPLE)
+	list(APPEND compat_SOURCES compat/darwin/regexec.c)
+	add_compile_definitions(DARWIN_REGEXEC)
 endif()
 
 
diff --git a/git-compat-util.h b/git-compat-util.h
index 8809776..96995c6 100644
--- a/git-compat-util.h
+++ b/git-compat-util.h
@@ -162,6 +162,9 @@ static inline int is_xplatform_dir_sep(int c)
 #include "compat/win32/path-utils.h"
 #include "compat/msvc.h"
 #endif
+#ifdef DARWIN_REGEXEC
+#include "compat/darwin.h"
+#endif
 
 /* used on Mac OS X */
 #ifdef PRECOMPOSE_UNICODE
@@ -992,6 +995,7 @@ static inline int strtol_i(char const *s, int base, int *result)
 #error "Git requires REG_STARTEND support. Compile with NO_REGEX=NeedsStartEnd"
 #endif
 
+#ifndef regexec_buf
 static inline int regexec_buf(const regex_t *preg, const char *buf, size_t size,
 			      size_t nmatch, regmatch_t pmatch[], int eflags)
 {
@@ -1000,6 +1004,7 @@ static inline int regexec_buf(const regex_t *preg, const char *buf, size_t size,
 	pmatch[0].rm_eo = size;
 	return regexec(preg, buf, nmatch, pmatch, eflags | REG_STARTEND);
 }
+#endif
 
 #ifdef USE_ENHANCED_BASIC_REGULAR_EXPRESSIONS
 int git_regcomp(regex_t *preg, const char *pattern, int cflags);
diff --git a/meson.build b/meson.build
index 3247697..53c4816 100644
--- a/meson.build
+++ b/meson.build
@@ -1387,6 +1387,11 @@ if not get_option('b_sanitize').contains('address') and get_option('regex').allo
     libgit_c_args += '-DUSE_ENHANCED_BASIC_REGULAR_EXPRESSIONS'
     compat_sources += 'compat/regcomp_enhanced.c'
   endif
+
+  if host_machine.system() == 'darwin'
+    libgit_c_args += '-DDARWIN_REGEXEC'
+    compat_sources += 'compat/darwin/regexec.c'
+  endif
 elif not get_option('regex').enabled()
   libgit_c_args += [
     '-DNO_REGEX',
diff --git a/t/t7810-grep.sh b/t/t7810-grep.sh
index d61c4a4..149654e 100755
--- a/t/t7810-grep.sh
+++ b/t/t7810-grep.sh
@@ -89,6 +89,10 @@ test_expect_success setup '
 	function dummy() {}
 	EOF
 	printf "\200\nASCII\n" >invalid-utf8 &&
+	printf "before\346world\n" >invalid-utf8-embedded &&
+	printf "a\346b\347c\n" >invalid-utf8-multi &&
+	printf "\346world\n" >invalid-utf8-leading &&
+	printf "before\346\n" >invalid-utf8-trailing &&
 	if test_have_prereq FUNNYNAMES
 	then
 		echo unusual >"\"unusual\" pathname" &&
@@ -595,6 +599,39 @@ test_expect_success MB_REGEX 'grep two chars in single-char multibyte file' '
 	LC_ALL=en_US.UTF-8 test_expect_code 1 git grep ".." reverse-question-mark
 '
 
+test_expect_success MACOS,MB_REGEX 'grep matches valid text on both sides of invalid UTF-8' '
+	LC_ALL=en_US.UTF-8 git grep -h "befo[r]e" invalid-utf8-embedded >actual &&
+	test_cmp invalid-utf8-embedded actual &&
+	LC_ALL=en_US.UTF-8 git grep -h "worl[d]" invalid-utf8-embedded >actual &&
+	test_cmp invalid-utf8-embedded actual &&
+	LC_ALL=en_US.UTF-8 git grep -h -o "worl[d]" invalid-utf8-embedded >actual &&
+	echo world >expected &&
+	test_cmp expected actual
+'
+
+test_expect_success MACOS,MB_REGEX 'grep matches a run between two invalid sequences' '
+	LC_ALL=en_US.UTF-8 git grep -h "[b]" invalid-utf8-multi >actual &&
+	test_cmp invalid-utf8-multi actual
+'
+
+test_expect_success MB_REGEX 'grep does not anchor ^ or $ inside an invalid-byte line' '
+	test_expect_code 1 env LC_ALL=en_US.UTF-8 \
+		git grep -h "^world" invalid-utf8-embedded &&
+	test_expect_code 1 env LC_ALL=en_US.UTF-8 \
+		git grep -h "before\$" invalid-utf8-embedded
+'
+
+test_expect_success MACOS,MB_REGEX 'grep anchors ^ and $ at true line ends past invalid UTF-8' '
+	LC_ALL=en_US.UTF-8 git grep -h "^before" invalid-utf8-embedded >actual &&
+	test_cmp invalid-utf8-embedded actual &&
+	LC_ALL=en_US.UTF-8 git grep -h "world\$" invalid-utf8-embedded >actual &&
+	test_cmp invalid-utf8-embedded actual &&
+	LC_ALL=en_US.UTF-8 git grep -h "^" invalid-utf8-leading >actual &&
+	test_cmp invalid-utf8-leading actual &&
+	LC_ALL=en_US.UTF-8 git grep -h "\$" invalid-utf8-trailing >actual &&
+	test_cmp invalid-utf8-trailing actual
+'
+
 cat >expected <<EOF
 file
 EOF
