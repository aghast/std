grammar STD:ver<6.0.0.alpha>:auth<http://perl.org>;

my $LANG is context;
my $PKGDECL is context = "";
my $PKG is context = "";
my @PKGS;
my $GOAL is context = "(eof)";
my $PARSER is context<rw>;
my $IN_DECL is context<rw>;
my %ROUTINES;

# random rule for debugging, please ignore
token foo {
   'foo' <.ws> 'bar' <.ws> 'baz'
}

=begin things todo

    add more suppositions and figure out exact error continuation semantics
    think about longest-token-defeating {*} that maybe should be <?{ {*}; 1}>
    add parsing this file to sanity tests :)
    evaluate "is context<rw>" for reentrancy brokenness

=end things todo

=begin comment overview

This file is designed to be either preprocessed into a grammar with
action statements or used as-is without any preprocessing.  The {*}
notation is a no-op action block, but can be identified uniquely via a
combination of the preceding token or rule name plus any additional text
following a #= comment.  We put this into a comment rather than using
a macro so that bootstrap compilers don't have to worry about macros
yet, and to keep the main grammar relatively uncluttered by action
statements.  Note that the preprocessor can certainly generate accesses
to the match state within the action block, so we need not mention it
explicitly.

Also, some rules are named by syntactic category plus an additonal symbol
specified in adverbial form, either in bare :name form or in :sym<name>
form.  (It does not matter which form you use for identifier symbols,
except that to specify a symbol "sym" you must use the :sym<sym> form
of adverb.)  If you use the <sym> rule within the rule, it will parse the
symbol at that point.  At the final reduction point of a rule, if $sym
has been set, that is used as the final symbol name for the rule.  This
need not match the symbol specified as part the rule name; that is just
for disambiguating the name.  However, if no $sym is set, the original
symbol will be used by default.

Note that rules with only one action need no #= comment, so the identifier
of the following stub is just "TOP".

Another nod toward preprocessing is that blocks that contain nested braces
are delimited by double braces so that the preprocessor does not need to
understand Perl 6 code.

This grammar also assumes transitive longest-token semantics, though
we make a feeble attempt to order rules so a procedural interpretation
of alternation can usually produce a correct parse.  (This will tend
to become less true over time.)

=end comment overview

method TOP ($STOP = undef) {
    if defined $STOP {
        my $GOAL is context = $STOP;
        self.unitstop($STOP).comp_unit;
    }
    else {
        self.comp_unit;
    }
}


# XXX shouldn't need this, it should all be defined/imported by the prelude

my @typenames = qw[
    Object Any Junction Whatever
    Capture Match Signature Proxy Matcher
    Package Module Class Role Grammar
    Scalar Array Hash KeyHash KeySet KeyBag
    Pair List Seq Range Set Bag Mapping
    Void Undef Failure Exception
    Code Block Routine Sub Macro
    Method Submethod Regex

    Str Blob
    Char Byte Codepoint Grapheme StrPos StrLen Version

    Num Complex
    num complex

    Int  int   int1  int2  int4 int8  int16  int32  int64
    Rat  rat   rat1  rat2  rat4 rat8  rat16  rat32  rat64
    UInt uint uint1 uint2 uint4 uint8 uint16 uint32 uint64
    Buf  buf   buf1  buf2  buf4 buf8  buf16  buf32  buf64

    Bit Bool
    bit bool

    Order Increasing Decreasing
    Ordered Callable Positional Associatve
    Ordering KeyExtractor Comparator OrderingPair

    IO

    KitchenSink
];
push @typenames, "True", "False", "Bool::True", "Bool::False";  # in quotes lest gimme5 translate them

my %typenames;
%typenames{@typenames} = (1 xx @typenames);

method is_type ($name) {
    return True if %typenames{$name};
    #return True if GLOBAL::{$name}.:exists;
    return False;
}

method add_type ($longname) {
    my $shortname = $longname.<name>.text;
    my $typename = main::mangle($shortname);
    my $qualname = ($+PKG // 'GLOBAL') ~ '::' ~ $typename;
    %typenames{$typename} = $qualname;
    %typenames{$qualname} = $qualname;
    %typenames{$shortname} = $qualname;
}

# XXX likewise for routine defs

my @routinenames = qw[
    WHAT WHICH VAR
    any all none one

    die exit warn
    caller want
    eval evalfile
    callsame callwith nextsame nextwith lastcall
    defined undefine item list slice eager hyper

    cat classify
    quotemeta
    chr ord
    p5chop chop p5chomp chomp
    index rindex substr
    join split comb pack unpack
    uc ucfirst lc lcfirst
    normalize
    nfc nfd nfkc nfkd
    samecase sameaccent
    capitalize
    chars graphs codes bytes

    say print open close printf sprintf slurp unlink link symlink
    elems grep map first reduce sort uniq push reverse take splice

    zip each roundrobin caller
    return leave pop shift unshift reduce
    keys values hash kv key value pairs pair

    sign abs floor ceiling round truncate
    exp log log10 sqrt roots
    rand srand pick
    cis unpolar

    sin cos tan asin acos atan sec cosec cotan asec acosec
    acotan sinh cosh tanh asinh acosh atanh sech cosech cotanh
    asech acosech acotanh atan2

    plan is ok dies_ok lives_ok skip todo pass flunk force_todo use_ok
    isa_ok cmp_ok diag is_deeply isnt like skip_rest unlike nonce
    skip_rest eval_dies_ok eval_lives_ok approx is_approx throws_ok version_lt

    gmtime localtime time times
    gethost getpw chroot getlogin
    run runinstead
    fork wait kill sleep
];
push @routinenames, "HOW", "fail", "temp", "let";

# please don't add: ref length bless delete exists

my %routinenames;
%routinenames{@routinenames} = (1 xx @routinenames);

method is_routine ($name) {
    return True if %routinenames{$name};
    return True if %typenames{$name};
    #return True if GLOBAL::{$name}.:exists;
    return False;
}

method add_routine ($name) {
    %routinenames{$name} = 1;
}

# The internal precedence levels are *not* part of the public interface.
# The current values are mere implementation; they may change at any time.
# Users should specify precedence only in relation to existing levels.

constant %term            = (:prec<z=>);
constant %methodcall      = (:prec<y=>);
constant %autoincrement   = (:prec<x=>);
constant %exponentiation  = (:prec<w=>, :assoc<right>, :assign);
constant %symbolic_unary  = (:prec<v=>);
constant %multiplicative  = (:prec<u=>, :assoc<left>,  :assign);
constant %additive        = (:prec<t=>, :assoc<left>,  :assign);
constant %replication     = (:prec<s=>, :assoc<left>,  :assign);
constant %concatenation   = (:prec<r=>, :assoc<left>,  :assign);
constant %junctive_and    = (:prec<q=>, :assoc<list>,  :assign);
constant %junctive_or     = (:prec<p=>, :assoc<list>,  :assign);
constant %named_unary     = (:prec<o=>);
constant %nonchaining     = (:prec<n=>, :assoc<non>);
constant %chaining        = (:prec<m=>, :assoc<chain>, :bool);
constant %tight_and       = (:prec<l=>, :assoc<left>,  :assign);
constant %tight_or        = (:prec<k=>, :assoc<left>,  :assign);
constant %conditional     = (:prec<j=>, :assoc<right>);
constant %item_assignment = (:prec<i=>, :assoc<right>);
constant %loose_unary     = (:prec<h=>);
constant %comma           = (:prec<g=>, :assoc<list>, :nextterm<nulltermish>);
constant %list_infix      = (:prec<f=>, :assoc<list>,  :assign);
constant %list_assignment = (:prec<i=>, :sub<e=>, :assoc<right>);
constant %list_prefix     = (:prec<e=>);
constant %loose_and       = (:prec<d=>, :assoc<left>,  :assign);
constant %loose_or        = (:prec<c=>, :assoc<left>,  :assign);
constant %sequencer      = (:prec<b=>, :assoc<left>, :nextterm<statement>);
constant %LOOSEST         = (:prec<a=!>);
constant %terminator      = (:prec<a=>, :assoc<list>);

# "epsilon" tighter than terminator
#constant $LOOSEST = %LOOSEST<prec>;
constant $LOOSEST = "a=!"; # XXX preceding line is busted


role PrecOp {

    # This is hopefully called on a match to mix in operator info by type.
    method coerce (Match $m) {
        # $m but= ::?CLASS;
        my $var = self.WHAT ~ '::o';
        my $d = %::($var); 
        if not $d<transparent> {
            for keys(%$d) { $m<O>{$_} = $d.{$_} };
            $m.deb("coercing to " ~ self) if $*DEBUG +& DEBUG::EXPR;
        }
        return $m;
    }

} # end role

class Hyper does PrecOp {
 our %o = (:transparent);
} # end class

class Term does PrecOp {
    our %o = %term;
} # end class
class Methodcall does PrecOp {
    our %o = %methodcall;
} # end class
class Autoincrement does PrecOp {
    our %o = %autoincrement;
} # end class
class Exponentiation does PrecOp {
    our %o = %exponentiation;
} # end class
class Symbolic_unary does PrecOp {
    our %o = %symbolic_unary;
} # end class
class Multiplicative does PrecOp {
    our %o = %multiplicative;
} # end class
class Additive does PrecOp {
    our %o = %additive;
} # end class
class Replication does PrecOp {
    our %o = %replication;
} # end class
class Concatenation does PrecOp {
    our %o = %concatenation;
} # end class
class Junctive_and does PrecOp {
    our %o = %junctive_and;
} # end class
class Junctive_or does PrecOp {
    our %o = %junctive_or;
} # end class
class Named_unary does PrecOp {
    our %o = %named_unary;
} # end class
class Nonchaining does PrecOp {
    our %o = %nonchaining;
} # end class
class Chaining does PrecOp {
    our %o = %chaining;
} # end class
class Tight_and does PrecOp {
    our %o = %tight_and;
} # end class
class Tight_or does PrecOp {
    our %o = %tight_or;
} # end class
class Conditional does PrecOp {
    our %o = %conditional;
} # end class
class Item_assignment does PrecOp {
    our %o = %item_assignment;
} # end class
class Loose_unary does PrecOp {
    our %o = %loose_unary;
} # end class
class Comma does PrecOp {
    our %o = %comma;
} # end class
class List_infix does PrecOp {
    our %o = %list_infix;
} # end class
class List_assignment does PrecOp {
    our %o = %list_assignment;
} # end class
class List_prefix does PrecOp {
    our %o = %list_prefix;
} # end class
class Loose_and does PrecOp {
    our %o = %loose_and;
} # end class
class Loose_or does PrecOp {
    our %o = %loose_or;
} # end class
class Sequencer does PrecOp {
    our %o = %sequencer;
} # end class
class Terminator does PrecOp {
    our %o = %terminator;
} # end class

# Categories are designed to be easily extensible in derived grammars
# by merely adding more rules in the same category.  The rules within
# a given category start with the category name followed by a differentiating
# adverbial qualifier to serve (along with the category) as the longer name.

# The endsym context, if specified, says what to implicitly check for in each
# rule right after the initial <sym>.  Normally this is used to make sure
# there's appropriate whitespace.  # Note that endsym isn't called if <sym>
# isn't called.

my $endsym is context = "null";
my $endargs is context = -1;

proto token category { <...> }

token category:category { <sym> }

token category:sigil { <sym> }
proto token sigil { <...> }

token category:twigil { <sym> }
proto token twigil { <...> }

token category:special_variable { <sym> }
proto token special_variable { <...> }

token category:version { <sym> }
proto token version { <...> }

token category:module_name { <sym> }
proto token module_name { <...> }

token category:term { <sym> }
proto token term { <...> }

token category:quote { <sym> }
proto token quote () { <...> }

token category:prefix { <sym> }
proto token prefix is unary is defequiv(%symbolic_unary) { <...> }

token category:infix { <sym> }
proto token infix is binary is defequiv(%additive) { <...> }

token category:postfix { <sym> }
proto token postfix is unary is defequiv(%autoincrement) { <...> }

token category:dotty { <sym> }
proto token dotty (:$endsym is context = 'unspacey') { <...> }

token category:circumfix { <sym> }
proto token circumfix { <...> }

token category:postcircumfix { <sym> }
proto token postcircumfix is unary { <...> }  # unary as far as EXPR knows...

token category:quote_mod { <sym> }
proto token quote_mod { <...> }

token category:trait_verb { <sym> }
proto token trait_verb (:$endsym is context = 'spacey') { <...> }

token category:trait_auxiliary { <sym> }
proto token trait_auxiliary (:$endsym is context = 'spacey') { <...> }

token category:type_declarator { <sym> }
proto token type_declarator () { <...> }

token category:scope_declarator { <sym> }
proto token scope_declarator () { <...> }

token category:package_declarator { <sym> }
proto token package_declarator () { <...> }

token category:multi_declarator { <sym> }
proto token multi_declarator () { <...> }

token category:routine_declarator { <sym> }
proto token routine_declarator () { <...> }

token category:regex_declarator { <sym> }
proto token regex_declarator () { <...> }

token category:statement_prefix { <sym> }
proto rule  statement_prefix () { <...> }

token category:statement_control { <sym> }
proto rule  statement_control (:$endsym is context = 'spacey') { <...> }

token category:statement_mod_cond { <sym> }
proto rule  statement_mod_cond () { <...> }

token category:statement_mod_loop { <sym> }
proto rule  statement_mod_loop () { <...> }

token category:infix_prefix_meta_operator { <sym> }
proto token infix_prefix_meta_operator is binary { <...> }

token category:infix_postfix_meta_operator { <sym> }
proto token infix_postfix_meta_operator ($op) is binary { <...> }

token category:infix_circumfix_meta_operator { <sym> }
proto token infix_circumfix_meta_operator is binary { <...> }

token category:postfix_prefix_meta_operator { <sym> }
proto token postfix_prefix_meta_operator is unary { <...> }

token category:prefix_postfix_meta_operator { <sym> }
proto token prefix_postfix_meta_operator is unary { <...> }

token category:prefix_circumfix_meta_operator { <sym> }
proto token prefix_circumfix_meta_operator is unary { <...> }

token category:terminator { <sym> }
proto token terminator { <...> }

token unspacey { <.unsp>? }
token spacey { <?before \s | '#'> }

# Lexical routines

token ws {
    :my @stub = return self if self.<_>[self.pos].:exists<ws>;
    :my $startpos = self.pos;

    [
	| \h+ <![#\s\\]> { $¢.<_>[$¢.pos]<ws> = $startpos; }	# common case
	| <?before \w> <?after \w> :::
	    { $¢.<_>[$startpos]<ws> = undef; }
	    <!>        # must \s+ between words
    ]
    ||
    [
    | <.unsp>
    | <.vws> <.heredoc>
    | <.unv>
    | $ { $¢.moreinput }
    ]*

    { $¢.<_>[$¢.pos]<ws> =
	$¢.pos == $startpos
	    ?? undef
	    !! $startpos;
    }
}

token unsp {
    \\ <?before [\s|'#'] >
    [
    | <.vws>                     {*}                             #= vwhite
    | <.unv>                  {*}                                #= unv
    | $ { $¢.moreinput }
    ]*
}

token vws {
    \v
    { $COMPILING::LINE++ } # XXX wrong several ways, use self.lineof($¢.pos)
    [ '#DEBUG -1' { say "DEBUG"; $STD::DEBUG = $*DEBUG = -1; } ]?
}

# We provide two mechanisms here:
# 1) define $+moreinput, or
# 2) override moreinput method
method moreinput () {
    $+moreinput.() if $+moreinput;
}

token unv {
   | \h+                 {*}                                    #= hwhite
   | <?before '='> ^^ <.pod_comment>  {*}                    #= pod
   | \h* '#' [
         |  <?opener>
            [ <!after ^^ . > || <.panic: "Can't use embedded comments in column 1"> ]
            <.quibble($¢.cursor_fresh( ::STD::Q ))>   {*}                               #= embedded
         | {} \N*            {*}                                 #= end
         ]
}

token ident {
    <.alpha> \w*
}

token apostrophe {
    <[ ' \- ]>
}

token identifier {
    <.ident> [ <.apostrophe> <.ident> ]*
}

# XXX We need to parse the pod eventually to support $= variables.

token pod_comment {
    ^^ '=' <.unsp>?
    [
    | 'begin' \h+ <identifier> :: .*?
      "\n=" <.unsp>? 'end' \h+ $<identifier> » \N*         {*}         #= tagged
    | 'begin' » :: \h* \n .*?
      "\n=" <.unsp>? 'end' » \N*                      {*}         #= anon
    | :: 
        [ <?before .*? ^^ '=cut' » > <.panic: "Obsolete pod format, please use =begin/=end instead"> ]?
        \N*                                           {*}         #= misc
    ]
}

# Top-level rules

# Note: we only check for the stopper.  We don't check for ^ because
# we might be embedded in something else.
rule comp_unit {
    :my $begin_compunit is context = 1;
    :my $endargs        is context<rw> = -1;

    <statementlist>
    [ <?unitstopper> || <.panic: "Can't understand next input--giving up"> ]
    # "CHECK" time...
    {{
        my %UNKNOWN;
        for keys(%ROUTINES) {
            next if $¢.is_routine($_);
            %UNKNOWN{$_} = %ROUTINES{$_};
        }
        if %UNKNOWN {
            warn "Unknown routines:\n";
            for sort keys(%UNKNOWN) {
                warn "\t$_ called at ", %UNKNOWN{$_}, "\n";
            }
        }
    }}
}

# Note: because of the possibility of placeholders we can't determine arity of
# the block syntactically, so this must be determined via semantic analysis.
# Also, pblocks used in an if/unless statement do not treat $_ as a placeholder,
# while most other blocks treat $_ as equivalent to $^x.  Therefore the first
# possible place to check arity is not here but in the rule that calls this
# rule.  (Could also be done in a later pass.)

token pblock {
    [ <lambda> <signature> ]? <block>
}

token lambda { '->' | '<->' }

# Look for an expression followed by a required lambda.
token xblock {
    :my $GOAL is context = '{';
    <EXPR>
    <.ws>
    <pblock>
}

token block {
    '{' <in: '}', 'statementlist', 'block'>

    [
    | <?before \h* $$> <.ws>	# (usual case without comments)
	{ $¢.<_>[$¢.pos]<endstmt> = 2; } {*}                    #= endstmt simple 
    | \h* <.unsp>? <?before <[,:]>> {*}                         #= normal 
    | <.unv>? $$ <.ws>
	{ $¢.<_>[$¢.pos]<endstmt> = 2; } {*}                    #= endstmt complex
    | {*} { $¢.<_>[$¢.pos]<endargs> = 1; }                      #= endargs
    ]
}

token regex_block {
    :my $lang = ::Regex;
    :my $GOAL is context = '}';

    [ <quotepair> <.ws>
	{
	    my $kv = $<quotepair>[*-1];
	    $lang = $lang.tweak($kv.<k>, $kv.<v>)
                or self.panic("Unrecognized adverb :" ~ $kv.<k> ~ '(' ~ $kv.<v> ~ ')');
	}
    ]*

    '{'
    <nibble( $¢.cursor_fresh($lang).unbalanced('}') )>
    [ '}' || <.panic: "Unable to parse regex; couldn't find right brace"> ]

    [
    | <?before \h* $$> <.ws>	# (usual case without comments)
	{ $¢.<_>[$¢.pos]<endstmt> = 2; } {*}                    #= endstmt simple 
    | \h* <.unsp>? <?before <[,:]>> {*}                         #= normal 
    | <.unv>? $$ <.ws>
	{ $¢.<_>[$¢.pos]<endstmt> = 2; } {*}                    #= endstmt complex
    | {*} { $¢.<_>[$¢.pos]<endargs> = 1; }                      #= endargs
    ]
}

# statement semantics
rule statementlist {
    :my $PARSER is context<rw> = self;
    [
    | $
    | <?before <[\)\]\}]> >
    | [<statement><.eat_terminator> ]*
    ]
}

# embedded semis, context-dependent semantics
rule semilist {
    [
    | <?before <[\)\]\}]> >
    | [<statement><.eat_terminator> ]*
    ]
}


token label {
    <identifier> ':' <?before \s> <.ws>

    [ <?{ $¢.is_type($<identifier>.text) }>
      <.panic("You tried to use an existing typename as a label")>
#      <suppose("You tried to use an existing name $/{'identifier'} as a label")>
    ]?

    # add label as a pseudo type
    # {{ eval 'COMPILING::{"::$<identifier>"} = Label.new($<identifier>)' }}  # XXX need statement ref too?

}

token statement {
    :my $endargs is context = -1;
    <!before <[\)\]\}]> >

    # this could either be a statement that follows a declaration
    # or a statement that is within the block of a code declaration
    <!!{ $¢ = $+PARSER.bless($¢); }>

    [
    | <label> <statement>                        {*}            #= label
    | <statement_control>                        {*}            #= control
    | <EXPR> {*}                                                #= expr
        [
        || <?{ ($¢.<_>[$¢.pos]<endstmt> // 0) == 2 }>   # no mod after end-line curly
        ||
            [
            | <statement_mod_loop> {*}                              #= mod loop
            | <statement_mod_cond> {*}                              #= mod cond
                [
                || <?{ ($¢.<_>[$¢.pos]<endstmt> // 0) == 2 }>
                || <statement_mod_loop>? {*}                          #= mod condloop
                ]
            ]?
        ]
        {*}                                                     #= modexpr
    | <?before ';'> {*}                                         #= null
    ]
}


token eat_terminator {
    [
    || ';'
    || <?{ $¢.<_>[$¢.pos]<endstmt> }>
    || <?before <terminator>>
    || $
    || {{ if $¢.<_>[$¢.pos]<ws> { $¢.pos = $¢.<_>[$¢.pos]<ws>; } }}   # undo any line transition
        <.panic: "Syntax error">
    ]
}

rule statement_control:use {\
    <sym>
    [
    | <version>
    | <module_name><arglist>?
        {{
            my $longname = $<module_name><longname>;
            $¢.add_type($longname);
        }}
    ]
}


rule statement_control:no {\
    <sym>
    <module_name><arglist>?
}


rule statement_control:if {\
    <sym>
    <xblock>
    $<elsif> = (
        'elsif'<?spacey> <xblock>       {*}                #= elsif
    )*
    $<else> = (
        'else'<?spacey> <pblock>       {*}             #= else
    )?
}


rule statement_control:unless {\
    <sym> 
    <xblock>
    [ <!before 'else'> || <.panic: "unless does not take \"else\" in Perl 6; please rewrite using \"if\""> ]
}


rule statement_control:while {\
    <sym>
    [ <?before '(' ['my'? '$'\w+ '=']? '<' '$'?\w+ '>' ')'>   #'
        <.panic: "This appears to be Perl 5 code"> ]?
    <xblock>
}


rule statement_control:until {\
    <sym>
    <xblock>
}


rule statement_control:repeat {\
    <sym>
    [
        | ('while'|'until')
          <xblock>
        | <block>                      {*}                      #= block wu
          ('while'|'until') <EXPR>         {*}                      #= expr wu
    ]
}


rule statement_control:loop {\
    <sym>
    $<eee> = (
        '('
            <e1=EXPR>? ';'   {*}                            #= e1
            <e2=EXPR>? ';'   {*}                            #= e2
            <e3=EXPR>?       {*}                            #= e3
        ')'                      {*}                            #= eee
    )?
    <block>                     {*}                             #= block
}


rule statement_control:for {\
    <sym>
    [ <?before 'my'? '$'\w+ '(' >
        <.panic: "This appears to be Perl 5 code"> ]?
    <xblock>
}

rule statement_control:given {\
    <sym>
    <xblock>
}
rule statement_control:when {\
    <sym>
    <xblock>
}
rule statement_control:default {<sym> <block> }

rule statement_control:BEGIN   {<sym> <block> }
rule statement_control:CHECK   {<sym> <block> }
rule statement_control:INIT    {<sym> <block> }
rule statement_control:END     {<sym> <block> }
rule statement_control:START   {<sym> <block> }
rule statement_control:ENTER   {<sym> <block> }
rule statement_control:LEAVE   {<sym> <block> }
rule statement_control:KEEP    {<sym> <block> }
rule statement_control:UNDO    {<sym> <block> }
rule statement_control:FIRST   {<sym> <block> }
rule statement_control:NEXT    {<sym> <block> }
rule statement_control:LAST    {<sym> <block> }
rule statement_control:PRE     {<sym> <block> }
rule statement_control:POST    {<sym> <block> }
rule statement_control:CATCH   {<sym> <block> }
rule statement_control:CONTROL {<sym> <block> }

rule term:BEGIN   {<sym> <block> }
rule term:CHECK   {<sym> <block> }
rule term:INIT    {<sym> <block> }
rule term:START   {<sym> <block> }
rule term:ENTER   {<sym> <block> }
rule term:FIRST   {<sym> <block> }

rule modifier_expr { <EXPR> }

rule statement_mod_cond:if     {<sym> <modifier_expr> {*} }     #= if
rule statement_mod_cond:unless {<sym> <modifier_expr> {*} }     #= unless
rule statement_mod_cond:when   {<sym> <modifier_expr> {*} }     #= when

rule statement_mod_loop:while {<sym> <modifier_expr> {*} }      #= while
rule statement_mod_loop:until {<sym> <modifier_expr> {*} }      #= until

rule statement_mod_loop:for   {<sym> <modifier_expr> {*} }      #= for
rule statement_mod_loop:given {<sym> <modifier_expr> {*} }      #= given

token module_name:normal {
    <longname>
    [ <?{ ($+PKGDECL//'') eq 'role' }> <?before '['> <postcircumfix> ]?
}

token module_name:deprecated { 'v6-alpha' }

token vnum {
    \d+ | '*'
}

token version:sym<v> {
    'v' <?before \d> :: <vnum> ** '.' '+'?
}

###################################################

token pre {
    [
    | <prefix>
        { $<O> = $<prefix><O>; $<sym> = $<prefix><sym> }
                                                    {*}         #= prefix
    | <prefix_circumfix_meta_operator>
        { $<O> = $<prefix_circumfix_meta_operator><O>; $<sym> = $<prefix_circumfix_meta_operator>.text }
                                                    {*}         #= precircum
    ]
    # XXX assuming no precedence change
    
    <prefix_postfix_meta_operator>*                 {*}         #= prepost
    { $+prevop = $<O> }
    <.ws>
}

# (for when you want to tell EXPR that infix already parsed the term)
token nullterm {
    <?>
}

token nulltermish {
    [
    | <?stdstopper>
    | <termish>?
    ]
}

token termish {
    [
    | <pre>+ <noun>
    | <noun>
    ]

    # also queue up any postfixes, since adverbs could change things
    [ <?stdstopper> ||
	<post>*
	<.ws>
	<adverbs>?
    ]
}

token adverbs {
    <!stdstopper>
    [ <colonpair> <.ws> ]+
    {
        my $prop = $+prevop orelse
            $¢.panic('No previous operator visible to adverbial pair');
#        $prop.adverb($<colonpair>);
    }
}

token noun {
    [
    | <fatarrow>
    | <variable> { $<sigil> = $<variable><sigil> }
    | <package_declarator>
    | <scope_declarator>
    | <?before 'multi'|'proto'|'only'> <multi_declarator>
    | <routine_declarator>
    | <regex_declarator>
    | <type_declarator>
    | <circumfix>
    | <dotty>
    | <value>
    | <capterm>
    | <sigterm>
    | <term>
    | <statement_prefix>
    | [ <colonpair> <.ws> ]+
    ]
}


token fatarrow {
    <key=identifier> \h* '=>' <.ws> <val=EXPR(item %item_assignment)>
}

token colonpair {
    :my $key;
    :my $value;

    ':'
    [
    | '!' <identifier>
        { $key = $<identifier>.text; $value = 0; }
        {*}                                                     #= false
    | <identifier>
        { $key = $<identifier>.text; }
        [
        || <.unsp>? '.'? <postcircumfix> { $value = $<postcircumfix>; }
        || { $value = 1; }
        ]
        {*}                                                     #= value
    | '(' <in: ')', 'signature'>
    | <postcircumfix>
        { $key = ""; $value = $<postcircumfix>; }
        {*}                                                     #= structural
    | $<var> = (<sigil> {} <twigil>? <desigilname>)
        { $key = $<var><desigilname>.text; $value = $<var>; }
        {*}                                                     #= varname
    ]
    { $<k> = $key; $<v> = $value; }
}

token quotepair {
    :my $key;
    :my $value;

    ':'
    [
    | '!' <identifier>
        { $key = $<identifier>.text; $value = 0; }
        {*}                                                     #= false
    | <identifier>
        { $key = $<identifier>.text; }
        [
        || <.unsp>? '.'? <?before '('> <postcircumfix> { $value = $<postcircumfix>; }
        || { $value = 1; }
        ]
        {*}                                                     #= value
    | $<n>=(\d+) $<id>=(<[a..z]>+)
        { $key = $<id>.text; $value = $<n>.text; }
        {*}                                                     #= nth
    ]
    { $<k> = $key; $<v> = $value; }
}

token infixish {
    <!stdstopper>
    <!infixstopper>
    [
    | <infix>
       [
       | ''
           { $<O> = $<infix>.<O>; $<sym> = $<infix>.<sym>; }
       | <?before '='> <infix_postfix_meta_operator($<infix>)>
           { $<O> = $<infix_postfix_meta_operator>.<O>; $<sym> = $<infix_postfix_meta_operator>.<sym>; }
       ]
    | <infix_prefix_meta_operator>
        { $<O> = $<infix_prefix_meta_operator><O>;
          $<sym> = $<infix_prefix_meta_operator><sym>; }
    | <infix_circumfix_meta_operator>
        { $<O> = $<infix_circumfix_meta_operator><O>;
          $<sym> = $<infix_circumfix_meta_operator><sym>; }
    ]
}

# doing fancy as one rule simplifies LTM
token dotty:sym<.*> ( --> Methodcall) {
    ('.' <[+*?=^:]>) <?unspacey> <dottyop>
    { $<sym> = $0.item; }
}

token dotty:sym<.> ( --> Methodcall) {
    <sym> <dottyop>
}

token privop ( --> Methodcall) {
    '!' <methodop>
}

token dottyop {
    [
    | <methodop>
    | <postop>     # forcing postop's precedence to methodcall here
    ]
}

# Note, this rule mustn't do anything irreversible because it's used
# as a lookahead by the quote interpolator.

token post {
    <!stdstopper>

    # last whitespace didn't end here
    <!{ $¢.<_>[$¢.pos]<ws> }>

    [ <.unsp> | '\\' <?before '.'> ]?

    [ ['.' <.unsp>?]? <postfix_prefix_meta_operator> <.unsp>? ]*

    [
    | <dotty>  { $<O> = $<dotty><O> }
    | <privop> { $<O> = $<privop><O> }
    | <postop> { $<O> = $<postop><O> }
    ]
    { $+prevop = $<O> }
}

regex prefix_circumfix_meta_operator:reduce (--> List_prefix) {
    $<s> = (
        '['
        [
        | <op=infix> ']' ['«'|<?>]
        | <op=infix_prefix_meta_operator> ']' ['«'|<?>]
        | <op=infix_circumfix_meta_operator> ']' ['«'|<?>]
        | \\<op=infix> ']' ['«'|<?>]
        | \\<op=infix_prefix_meta_operator> ']' ['«'|<?>]
        | \\<op=infix_circumfix_meta_operator> ']' ['«'|<?>]
        ]
    ) <?before \s | '(' >

    { $<O> = $<s><op><O>; $<sym> = $<s>.text; }

    [ <!{ $<O><assoc> eq 'non' }>
        || <.panic: "Can't reduce a non-associative operator"> ]

    [ <!{ $<O><prec> eq %conditional<prec> }>
        || <.panic: "Can't reduce a conditional operator"> ]

    { $<O><assoc> = 'unary'; }

}

token prefix_postfix_meta_operator:sym< « >    { <sym> | '<<' }

token postfix_prefix_meta_operator:sym< » >    { <sym> | '>>' }

token infix_prefix_meta_operator:sym<!> ( --> Chaining) {
    <sym> <!before '!'> <infix>

    <!!{ $<O> = $<infix><O>; }>
    <!!lex1: 'negation'>

    [
    || <!!{ $<O><assoc> eq 'chain'}>
    || <!!{ $<O><assoc> and $<O><bool> }>
    || <.panic: "Only boolean infix operators may be negated">
    ]

    <!{ $<O><hyper> and $¢.panic("Negation of hyper operator not allowed") }>

}

method lex1 (Str $s) {
    self.<O>{$s}++ and self.panic("Nested $s metaoperators not allowed");
    self;
}

token infix_circumfix_meta_operator:sym<X X> ( --> List_infix) {
    X <infix> X
    <!!{ $<O> = $<infix><O>; }>
    <!!lex1: 'cross'>
}

token infix_circumfix_meta_operator:sym<« »> ( --> Hyper) {
    [
    | '«' <infix> [ '«' | '»' ]
    | '»' <infix> [ '«' | '»' ]
    | '<<' <infix> [ '<<' | '>>' ]
    | '>>' <infix> [ '<<' | '>>' ]
    ]
    <!!{ $<O> := $<infix><O>; }>
    <!!lex1: 'hyper'>
}

token infix_postfix_meta_operator:sym<=> ($op --> Item_assignment) {
    '='
    { $<O> = $op<O>; }
    <?lex1: 'assignment'>

    [ <?{ ($<O><assoc> // '') eq 'chain' }> <.panic: "Can't make assignment op of boolean operator"> ]?
    [ <?{ ($<O><assoc> // '') eq 'non'   }> <.panic: "Can't make assignment op of non-associative operator"> ]?
}

token postcircumfix:sym<( )> ( --> Methodcall)
    { '(' <in: ')', 'semilist', 'argument list'> }

token postcircumfix:sym<[ ]> ( --> Methodcall)
    { '[' <in: ']', 'semilist', 'subscript'> }

token postcircumfix:sym<{ }> ( --> Methodcall)
    { '{' <in: '}', 'semilist', 'subscript'> }

token postcircumfix:sym«< >» ( --> Methodcall)
    { '<' <nibble($¢.cursor_fresh( ::STD::Q ).tweak(:q).tweak(:w).balanced('<','>'))> [ '>' || <.panic: "Unable to parse quote-words subscript; couldn't find right angle quote"> ] }

token postcircumfix:sym«<< >>» ( --> Methodcall)
    { '<<' <nibble($¢.cursor_fresh( ::STD::Q ).tweak(:qq).tweak(:ww).balanced('<<','>>'))> [ '>>' || <.panic: "Unable to parse quote-words subscript; couldn't find right double-angle quote"> ] }

token postcircumfix:sym<« »> ( --> Methodcall)
    { '«' <nibble($¢.cursor_fresh( ::STD::Q ).tweak(:qq).tweak(:ww).balanced('«','»'))> [ '»' || <.panic: "Unable to parse quote-words subscript; couldn't find right double-angle quote"> ] }

token postop {
    | <postfix>         { $<O> := $<postfix><O> }
    | <postcircumfix>   { $<O> := $<postcircumfix><O> }
}

token methodop {
    [
    | <longname>
    | <?before '$' | '@' > <variable>
    | <?before <[ ' " ]> > <quote>
        { $<quote> ~~ /\W/ or $¢.panic("Useless use of quotes") }
    ] <.unsp>? 

    [
    | '.'? <.unsp>? '(' <in: ')', 'semilist', 'argument list'>
    | ':' <?before \s> <!{ $+inquote }> <arglist>
    ]?
}

token arglist {
    :my StrPos $endargs is context<rw> = 0;
    <.ws>
    [
    | <?stdstopper>
    | <EXPR(item %list_prefix)>
    ]
}

token circumfix:sym<{ }> ( --> Term) {
    <?before '{' | <lambda> > <pblock>
}

token variable_declarator {
    :my $IN_DECL is context<rw> = 1;
    <variable> { $<sigil> = $<variable><sigil> }
    { $IN_DECL = 0; }
    [   # Is it a shaped array or hash declaration?
      #  <?{ $<sigil> eq '@' | '%' }>
        <.unsp>?
        [
        | '(' <in: ')', 'signature'>
        | '[' <in: ']', 'semilist', 'shape definition'>
        | '{' <in: '}', 'semilist', 'shape definition'>
        | <?before '<'> <postcircumfix>
        ]*
    ]?
    <.ws>

    <trait>*

    <post_constraint>*

    [
    | '=' <.ws> <EXPR( ($<sigil> // '') eq '$' ?? item %item_assignment !! item %list_prefix )>
    | '.=' <.ws> <dottyop>
    ]?
}

rule scoped {
    [
    | <declarator>
    | <regex_declarator>
    | <package_declarator>
    | <fulltypename>+ <multi_declarator>
    | <multi_declarator>
#    | <?before <[A..Z]> > <name> <.panic("Apparent type name " ~ $<name>.text ~ " is not declared yet")>
    ]
}


token scope_declarator:my       { <sym> <scoped> }
token scope_declarator:our      { <sym> <scoped> }
token scope_declarator:state    { <sym> <scoped> }
token scope_declarator:constant { <sym> <scoped> }
token scope_declarator:has      { <sym> <scoped> }


token package_declarator:class {
    :my $PKGDECL is context = 'class';
    <sym> <package_def>
}

token package_declarator:grammar {
    :my $PKGDECL is context = 'grammar';
    <sym> <package_def>
}

token package_declarator:module {
    :my $PKGDECL is context = 'module';
    <sym> <package_def>
}

token package_declarator:package {
    :my $PKGDECL is context = 'package';
    <sym> <package_def>
}

token package_declarator:role {
    :my $PKGDECL is context = 'role';
    <sym> <package_def>
}

token package_declarator:require {   # here because of declarational aspects
    <sym> <.ws>
    <module_name> <EXPR>?
}

token package_declarator:trusts {
    <sym> <.ws>
    <module_name>
}

token package_declarator:does {
    <sym> <.ws>
    <typename>
}

rule package_def {
    :my $longname;
    [
	<module_name>{
            $longname = $<module_name>[0]<longname>;
            $¢.add_type($longname);
        }
    ]?
    <trait>*
    [
       <?before '{'>
       {{
	   # figure out the actual full package name (nested in outer package)
            my $pkg = $+PKG // "GLOBAL";
	    push @PKGS, $pkg;
	    if $longname {
		my $shortname = $longname.<name>.text;
		$+PKG = $pkg ~ '::' ~ $shortname;
	    }
	    else {
		$+PKG = $pkg ~ '::_anon_';
	    }
	}}
        <block>
	{{
	    $+PKG = pop(@PKGS);
	}}
	{*}                                                     #= block
    || <?{ $+begin_compunit }> {} <?before ';'>
        {
            $longname orelse $¢.panic("Compilation unit cannot be anonymous");
	    my $shortname = $longname.<name>.text;
	    $+PKG = $shortname;
            $+begin_compunit = 0;
        }
        {*}                                                     #= semi
    || <.panic: "Unable to parse " ~ $+PKGDECL ~ " definition">
    ]
}

token declarator {
    [
    | <variable_declarator>
    | '(' <in: ')', 'signature'> <trait>*
    | <routine_declarator>
    | <regex_declarator>
    | <type_declarator>
    ]
}

token multi_declarator:multi { <sym> <.ws> [ <declarator> || <routine_def> ] }
token multi_declarator:proto { <sym> <.ws> [ <declarator> || <routine_def> ] }
token multi_declarator:only  { <sym> <.ws> [ <declarator> || <routine_def> ] }
token multi_declarator:null  { <declarator> }

token routine_declarator:sub       { <sym> <routine_def> }
token routine_declarator:method    { <sym> <method_def> }
token routine_declarator:submethod { <sym> <method_def> }
token routine_declarator:macro     { <sym> <macro_def> }

token regex_declarator:regex { <sym>       <regex_def> }
token regex_declarator:token { <sym>       <regex_def> }
token regex_declarator:rule  { <sym>       <regex_def> }

# Most of these special variable rules are there simply to catch old p5 brainos

token special_variable:sym<$¢> { <sym> }

token special_variable:sym<$!> { <sym> <!before \w> }

token special_variable:sym<$!{ }> {
    # XXX the backslashes are necessary here for bootstrapping, not for P6...
    ( '$!{' :: (.*?) '}' )
    <obs($0.text ~ " variable", 'smart match against $!')>
}

token special_variable:sym<$/> {
    <sym>
    # XXX assuming nobody ever wants to assign $/ directly anymore...
    [ <?before \h* '=' <![=]> >
        <obs('$/ variable as input record separator',
             "filehandle's :irs attribute")>
    ]?
}

token special_variable:sym<$~> {
    <sym> :: <?before \s | ',' | '=' | <terminator> >
    <obs('$~ variable', 'Form module')>
}

token special_variable:sym<$`> {
    <sym> :: <?before \s | ',' | <terminator> >
    <obs('$` variable', 'explicit pattern before <(')>
}

token special_variable:sym<$@> {
    <sym> ::
    <obs('$@ variable as eval error', '$!')>
}

token special_variable:sym<$#> {
    <sym> ::
    [
    || (\w+) <obs("\$#" ~ $0.text ~ " variable", "\@{" ~ $0.text ~ "}.end")>
    || <obs('$# variable', '.fmt')>
    ]
}
token special_variable:sym<$$> {
    <sym> <!alpha> :: <?before \s | ',' | <terminator> >
    <obs('$$ variable', '$*PID')>
}
token special_variable:sym<$%> {
    <sym> ::
    <obs('$% variable', 'Form module')>
}

# Note: this works because placeholders are restricted to lowercase
token special_variable:sym<$^X> {
    <sigil> '^' $<letter> = [<[A..Z]>] \W
    <obscaret($<sigil>.text ~ '^' ~ $<letter>.text, $<sigil>, $<letter>.text)>
}

token special_variable:sym<$^> {
    <sym> :: <?before \s | ',' | '=' | <terminator> >
    <obs('$^ variable', 'Form module')>
}

token special_variable:sym<$&> {
    <sym> :: <?before \s | ',' | <terminator> >
    <obs('$& variable', '$/ or $()')>
}

token special_variable:sym<$*> {
    <sym> :: <?before \s | ',' | '=' | <terminator> >
    <obs('$* variable', '^^ and $$')>
}

token special_variable:sym<$)> {
    <sym> :: <?before \s | ',' | <terminator> >
    <obs('$) variable', '$*EGID')>
}

token special_variable:sym<$-> {
    <sym> :: <?before \s | ',' | '=' | <terminator> >
    <obs('$- variable', 'Form module')>
}

token special_variable:sym<$=> {
    <sym> :: <?before \s | ',' | '=' | <terminator> >
    <obs('$= variable', 'Form module')>
}

token special_variable:sym<@+> {
    <sym> :: <?before \s | ',' | <terminator> >
    <obs('@+ variable', '.to method')>
}

token special_variable:sym<%+> {
    <sym> :: <?before \s | ',' | <terminator> >
    <obs('%+ variable', '.to method')>
}

token special_variable:sym<$+[ ]> {
    '$+['
    <obs('@+ variable', '.to method')>
}

token special_variable:sym<@+[ ]> {
    '@+['
    <obs('@+ variable', '.to method')>
}

token special_variable:sym<@+{ }> {
    '@+{'
    <obs('%+ variable', '.to method')>
}

token special_variable:sym<@-> {
    <sym> :: <?before \s | ',' | <terminator> >
    <obs('@- variable', '.from method')>
}

token special_variable:sym<%-> {
    <sym> :: <?before \s | ',' | <terminator> >
    <obs('%- variable', '.from method')>
}

token special_variable:sym<$-[ ]> {
    '$-['
    <obs('@- variable', '.from method')>
}

token special_variable:sym<@-[ ]> {
    '@-['
    <obs('@- variable', '.from method')>
}

token special_variable:sym<%-{ }> {
    '@-{'
    <obs('%- variable', '.from method')>
}

token special_variable:sym<$+> {
    <sym> :: <?before \s | ',' | <terminator> >
    <obs('$+ variable', 'Form module')>
}

token special_variable:sym<${^ }> {
    ( <sigil> '{^' :: (.*?) '}' )
    <obscaret($0.text, $<sigil>, $0.{0}.text)>
}

# XXX should eventually rely on multi instead of nested cases here...
method obscaret (Str $var, Str $sigil, Str $name) {
    my $repl = do { given $sigil {
        when '$' {
            given $name {
                when 'MATCH'         { '$/' }
                when 'PREMATCH'      { 'an explicit pattern before <(' }
                when 'POSTMATCH'     { 'an explicit pattern after )>' }
                when 'ENCODING'      { '$?ENCODING' }
                when 'UNICODE'       { '$?UNICODE' }  # XXX ???
                when 'TAINT'         { '$*TAINT' }
                when 'OPEN'          { 'filehandle introspection' }
                when 'N'             { '$-1' } # XXX ???
                when 'L'             { 'Form module' }
                when 'A'             { 'Form module' }
                when 'E'             { '$!.extended_os_error' }
                when 'C'             { 'COMPILING namespace' }
                when 'D'             { '$*DEBUGGING' }
                when 'F'             { '$*SYSTEM_FD_MAX' }
                when 'H'             { '$?FOO variables' }
                when 'I'             { '$*INPLACE' } # XXX ???
                when 'O'             { '$?OS or $*OS' }
                when 'P'             { 'whatever debugger Perl 6 comes with' }
                when 'R'             { 'an explicit result variable' }
                when 'S'             { 'the context function' } # XXX ???
                when 'T'             { '$*BASETIME' }
                when 'V'             { '$*PERL_VERSION' }
                when 'W'             { '$*WARNING' }
                when 'X'             { '$*EXECUTABLE_NAME' }
                when *               { "a global form such as $sigil*$name" }
            }
        }
        when '%' {
            given $name {
                when 'H'             { '$?FOO variables' }
                when *               { "a global form such as $sigil*$name" }
            }
        }
        when * { "a global form such as $sigil*$name" }
    };
    };
    return self.obs("$var variable", $repl);
}

token special_variable:sym<::{ }> {
    '::' <?before '{'>
}

token special_variable:sym<${ }> {
    ( <[$@%]> '{' :: (.*?) '}' )
    <obs("" ~ $0.text ~ " variable", "{" ~ $<sigil>.text ~ "}(" ~ $0.{0}.text ~ ")")>
}

token special_variable:sym<$[> {
    <sym> :: <?before \s | ',' | '=' | <terminator> >
    <obs('$[ variable', 'user-defined array indices')>
}

token special_variable:sym<$]> {
    <sym> :: <?before \s | ',' | <terminator> >
    <obs('$] variable', '$*PERL_VERSION')>
}

token special_variable:sym<$\\> {
    <sym> :: <?before \s | ',' | '=' | <terminator> >
    <obs('$\\ variable', "the filehandle's :ors attribute")>
}

token special_variable:sym<$|> {
    <sym> :: <?before \s | ',' | '=' | <terminator> >
    <obs('$| variable', 'Form module')>
}

token special_variable:sym<$:> {
    <sym> <?before <[\x20\t\n\],=)}]> >
    <obs('$: variable', 'Form module')>
}

token special_variable:sym<$;> {
    <sym> :: <?before \s | ',' | '=' | <terminator> >
    <obs('$; variable', 'real multidimensional hashes')>
}

token special_variable:sym<$'> { #'
    <sym> :: <?before \s | ',' | <terminator> >
    <obs('$' ~ "'" ~ 'variable', "explicit pattern after )\x3E")>
}

token special_variable:sym<$"> {
    <sym> :: <?before \s | ',' | '=' | <terminator> >
    <obs('$" variable', '.join() method')>
}

token special_variable:sym<$,> {
    <sym> :: <?before \s | ',' | <terminator> >
    <obs('$, variable', ".join() method")>
}

token special_variable:sym['$<'] {
    <sym> :: <!before \s* \w+ \s* '>' >
    <obs('$< variable', '$*UID')>
}

token special_variable:sym«\$>» {
    <sym> :: <?before \s | ',' | <terminator> >
    <obs("$() variable", '$*EUID')>
}

token special_variable:sym<$.> {
    <sym> :: <?before \s | ',' | <terminator> >
    <obs('$. variable', "filehandle's .line method")>
}

token special_variable:sym<$?> {
    <sym> :: <?before \s | ',' | <terminator> >
    <obs('$? variable as child error', '$!')>
}

# desigilname should only follow a sigil/twigil

token desigilname {
    [
    | <?before '$' > <variable>
    | <longname>
    ]
}

token variable {
    <?before <sigil> > {}
    [
    || '&' <twigil>?  <sublongname> {*}                                   #= subnoun
    || <?before '$::('> '$' <name>?
    || '$::' <name>? # XXX
    || '$:' <name>? # XXX
    || [
        | <sigil> <twigil>? <desigilname> {*}                                    #= desigilname
            [ <?{ $<twigil> eq '.' }>
                <.unsp>? <?before '('> <postcircumfix> {*}          #= methcall
            ]?
        | <special_variable> {*}                                    #= special
        | <sigil> \d+ {*}                                           #= $0
        # Note: $() can also parse as contextualizer in an expression; should have same effect
        | <sigil> <?before '<' | '('> <postcircumfix> {*}           #= $()
	| <sigil> <?{ $+IN_DECL }> {*}				    #= anondecl
        ]
    ]
}

# Note, don't reduce on a bare sigil unless you don't want a twigil or
# you otherwise don't care what the longest token is.

token sigil:sym<$>  { <sym> }
token sigil:sym<@@> { <sym> }
token sigil:sym<@>  { <sym> }
token sigil:sym<%>  { <sym> }
token sigil:sym<&>  { <sym> }

token twigil:sym<.> { <sym> }
token twigil:sym<!> { <sym> }
token twigil:sym<^> { <sym> }
token twigil:sym<:> { <sym> <!before ':'> }
token twigil:sym<*> { <sym> }
token twigil:sym<+> { <sym> }
token twigil:sym<?> { <sym> }
token twigil:sym<=> { <sym> }

token deflongname {
    <name>
    # XXX too soon
    [ <colonpair>+ { $¢.add_macro($<name>) if $+IN_DECL; } ]?
    { $¢.add_routine($<name>.text) if $+IN_DECL; }
}

token longname {
    <name> <colonpair>*
}

token name {
    [
    | <identifier> <morename>*
    | <morename>+
    ]
}

token morename {
    '::'
    [
        <?before '(' | <alpha> >
        [
        | <identifier>
        | '(' <in: ')', 'EXPR', 'indirect name'>
        ]
    ]?
}

token subshortname {
    [
    | <category>
        [ <colonpair>+ { $¢.add_macro($<category>) if $+IN_DECL; } ]?
    | <desigilname> { $¢.add_routine($<desigilname>.text) if $+IN_DECL; }
    ]
}

token sublongname {
    <subshortname> <sigterm>?
}

#token subcall {
#    # XXX should this be sublongname?
#    <subshortname> <.unsp>? '.'? '(' <in: ')', 'semilist'>
#    {*}
#}

#token packagevar {
#    # Note: any ::() are handled within <name>, and subscript must be final part.
#    # A bare ::($foo) is not considered a variable, but ::($foo)::<$bar> is.
#    # (The point being that we want a sigil either first or last but not both.)
#    <?before [\w+] ** '::' [ '<' | '«' | '{' ]> ::
#    <name> '::' <postcircumfix> {*}                            #= FOO::<$x>
#}

token value {
    [
    | <quote>
    | <number>
    | <version>
#    | <packagevar>     # XXX see term:name for now
#    | <fulltypename>   # XXX see term:name for now
    ]
}

token typename {
    [
    | '::?'<identifier>			# parse ::?CLASS as special case
    | <longname>
      <?{
        my $longname = $<longname>.text;
        substr($longname, 0, 2) eq '::' or $¢.is_type($longname)
      }>
    ]
    # parametric type?
    <.unsp>? [ <?before '['> <postcircumfix> ]?
}

rule fulltypename {<typename>['|'<typename>]*
    [ of <fulltypename> ]?
}

token number {
    [
    | <dec_number>
    | <integer>
    | <rad_number>
    ]
}

token integer {
    [
    | 0 [ b <[01]>+           [ _ <[01]>+ ]*
        | o <[0..7]>+         [ _ <[0..7]>+ ]*
        | x <[0..9a..fA..F]>+ [ _ <[0..9a..fA..F]>+ ]*
        | d \d+               [ _ \d+]*
        | \d+[_\d+]*
            { $¢.worry("Leading 0 does not indicate octal in Perl 6") }
        ]
    | \d+[_\d+]*
    ]
}

token radint {
    [
    | <integer>
    | <?before ':'> <rad_number> <?{
                        defined $<rad_number><intpart>
                        and
                        not defined $<rad_number><fracpart>
                    }>
    ]
}

token escale {
    <[Ee]> <[+\-]>? \d+[_\d+]*
}

# careful to distinguish from both integer and 42.method
token dec_number {
    [
    | $<coeff> = [           '.' \d+[_\d+]* ] <escale>?
    | $<coeff> = [\d+[_\d+]* '.' \d+[_\d+]* ] <escale>?
    | $<coeff> = [\d+[_\d+]*                ] <escale>
    ]
}

token rad_number {
    ':' $<radix> = [\d+] <.unsp>?      # XXX optional dot here?
    {}           # don't recurse in lexer
    [
    || '<'
            $<intpart> = <[ 0..9 a..z A..Z ]>+ [ _ <[ 0..9 a..z A..Z ]>+ ]*
            $<fracpart> = [ '.' <[ 0..9 a..z A..Z ]>+ [ _ <[ 0..9 a..z A..Z ]>+ ]* ]?
            [ '*' <base=radint> '**' <exp=radint> ]?
       '>'
#      { make radcalc($<radix>, $<intpart>, $<fracpart>, $<base>, $<exp>) }
    || <?before '['> <postcircumfix>
    || <?before '('> <postcircumfix>
    ]
}

token octint {
    <[ 0..7 ]>+ [ _ <[ 0..7 ]>+ ]*
}

token hexint {
    <[ 0..9 a..f A..F ]>+ [ _ <[ 0..9 a..f A..F ]>+ ]*
}

our @herestub_queue;

class Herestub {
    has Str $.delim;
    has $.orignode;
    has $.lang;
} # end class

role herestop {
    token stopper { ^^ {*} $<ws>=(\h*?) $+DELIM \h* <.unv>?? $$ \v? }
} # end role

# XXX be sure to temporize @herestub_queue on reentry to new line of heredocs

method heredoc () {
    temp $CTX = self.callm if $*DEBUG +& DEBUG::trace_call;
    return if self.peek;
    my $here = self;
    while my $herestub = shift @herestub_queue {
        my $DELIM is context = $herestub.delim;
        my $lang = $herestub.lang.mixin( ::herestop );
        my $doc;
        if ($doc) = $here.nibble($lang) {
            $here = $doc.trim_heredoc();
            $herestub.orignode<doc> = $doc;
        }
        else {
            self.panic("Ending delimiter $DELIM not found");
        }
    }
    return self.cursor($here.pos);  # return to initial type
}

proto token backslash { <...> }
proto token escape { <...> }
token starter { <!> }
token escape:none { <!> }

token babble ($l) {
    :my $lang = $l;
    :my $start;
    :my $stop;

    <.ws>
    [ <quotepair> <.ws>
	{
	    my $kv = $<quotepair>[*-1];
	    $lang = $lang.tweak($kv.<k>, $kv.<v>)
                or self.panic("Unrecognized adverb :" ~ $kv.<k> ~ '(' ~ $kv.<v> ~ ')');
	}
    ]*

    {
        ($start,$stop) = $¢.peek_delimiters();
        $lang = $start ne $stop ?? $lang.balanced($start,$stop)
                                !! $lang.unbalanced($stop);
        $<B> = [$lang,$start,$stop];
    }
}

token quibble ($l) {
    :my ($lang, $start, $stop);
    <babble($l)>
    { my $B = $<babble><B>; ($lang,$start,$stop) = @$B; }

    $start <nibble($lang)> $stop

    {{
        if $lang<_herelang> {
            push @herestub_queue,
                STD::Herestub.new(
                    delim => $<nibble><nibbles>[0],
                    orignode => $¢,
                    lang => $lang<_herelang>,
                );
        }
    }}
}

token sibble ($l, $lang2) {
    :my ($lang, $start, $stop);
    <babble($l)>
    { my $B = $<babble><B>; ($lang,$start,$stop) = @$B; }

    $start <left=nibble($lang)> $stop 
    [ <?{ $start ne $stop }>
	<.ws>
        [ '=' || <.panic: "Missing '='"> ]
        <.ws>
        <right=EXPR(item %item_assignment)>
    || 
	{ $lang = $lang2.unbalanced($stop); }
	<right=nibble($lang)> $stop
    ]
}

token tribble ($l, $lang2 = $l) {
    :my ($lang, $start, $stop);
    <babble($l)>
    { my $B = $<babble><B>; ($lang,$start,$stop) = @$B; }

    $start <left=nibble($lang)> $stop 
    [ <?{ $start ne $stop }>
	<.ws> <quibble($lang2)>
    || 
	{ $lang = $lang2.unbalanced($stop); }
	<right=nibble($lang)> $stop
    ]
}

token quasiquibble ($l) {
    :my ($lang, $start, $stop);
    <babble($l)>
    { my $B = $<babble><B>; ($lang,$start,$stop) = @$B; }

    [
    || <?{ $start eq '{' }> [ :lang($lang) <block> ]
    || $start [ :lang($lang) <statementlist> ] $stop
    ]
}

# note: polymorphic over many quote languages, we hope
token nibbler {
    :my $text = '';
    :my @nibbles = ();
    :my $buf = self.orig;
    :my $multiline = 0;
    { $<firstpos> = self.pos; }
    [ <!before <stopper> >
        [
        || <starter> <nibbler> <stopper>
                        {
                            my $n = $<nibbler>[*-1]<nibbles>;
                            my @n = @$n;
                            $text ~= $<starter>[*-1].text ~ shift(@n);
                            $text = (@n ?? pop(@n) !! '') ~ $<stopper>[*-1].text;
                            push @nibbles, @n;
                        }
        || <escape>   {
                            push @nibbles, $text, $<escape>;
                            $text = '';
                        }
        || .
                        {{
                            my $ch = substr($$buf, $¢.pos-1, 1);
                            $text ~= $ch;
                            if $ch ~~ "\n" {
                                $multiline++;
                                $COMPILING::LINE++; # bypasses <vws>
                            }
                        }}
        ]
    ]*
    {
        push @nibbles, $text; $<nibbles> = [@nibbles];
        $<lastpos> = $¢.pos;
        $COMPILING::LAST_NIBBLE = $¢;
        $COMPILING::LAST_NIBBLE_MULTILINE = $¢ if $multiline;
    }
}

# and this is what makes nibbler polymorphic...
method nibble ($lang) {
    my $outerlang = self.WHAT;
    my $LANG is context = $outerlang;
    self.cursor_fresh($lang).nibbler;
}


token quote:sym<' '>   { "'" <nibble($¢.cursor_fresh( ::STD::Q ).tweak(:q).unbalanced("'"))> "'" }
token quote:sym<" ">   { '"' <nibble($¢.cursor_fresh( ::STD::Q ).tweak(:qq).unbalanced('"'))> '"' }

token quote:sym<« »>   { '«' <nibble($¢.cursor_fresh( ::STD::Q ).tweak(:qq).tweak(:ww).balanced('«','»'))> '»' }
token quote:sym«<< >>» { '<<' <nibble($¢.cursor_fresh( ::STD::Q ).tweak(:qq).tweak(:ww).balanced('<<','>>'))> '>>' }
token quote:sym«< >»   { '<' <nibble($¢.cursor_fresh( ::STD::Q ).tweak(:q).tweak(:w).balanced('<','>'))> '>' }

token quote:sym</ />   {
    '/' <nibble( $¢.cursor_fresh( ::Regex ).unbalanced("/") )> [ '/' || <.panic: "Unable to parse regex; couldn't find final '/'"> ]
    <.old_rx_mods>?
}

# handle composite forms like qww
token quote:qq {
    :my $qm;
    'qq'
    [
    | <quote_mod> » <!before '('> { $qm = $<quote_mod>.text } <.ws> <quibble($¢.cursor_fresh( ::STD::Q ).tweak(:qq).tweak($qm => 1))>
    | » <!before '('> <.ws> <quibble($¢.cursor_fresh( ::STD::Q ).tweak(:qq))>
    ]
}
token quote:q {
    :my $qm;
    'q'
    [
    | <quote_mod> » <!before '('> { $qm = $<quote_mod>.text } <quibble($¢.cursor_fresh( ::STD::Q ).tweak(:q).tweak($qm => 1))>
    | » <!before '('> <.ws> <quibble($¢.cursor_fresh( ::STD::Q ).tweak(:q))>
    ]
}

token quote:Q {
    :my $qm;
    'Q'
    [
    | <quote_mod> » <!before '('> { $qm = $<quote_mod>.text } <quibble($¢.cursor_fresh( ::STD::Q ).tweak($qm => 1))>
    | » <!before '('> <.ws> <quibble($¢.cursor_fresh( ::STD::Q ))>
    ]
}

token quote_mod:w  { <sym> }
token quote_mod:ww { <sym> }
token quote_mod:x  { <sym> }
token quote_mod:to { <sym> }
token quote_mod:s  { <sym> }
token quote_mod:a  { <sym> }
token quote_mod:h  { <sym> }
token quote_mod:f  { <sym> }
token quote_mod:c  { <sym> }
token quote_mod:b  { <sym> }

token quote:rx {
    <sym> » <!before '('>
    <quibble( $¢.cursor_fresh( ::Regex ) )>
    <!old_rx_mods>
}

token quote:m  {
    <sym> » <!before '('>
    <quibble( $¢.cursor_fresh( ::Regex ) )>
    <!old_rx_mods>
}

token quote:mm {
    <sym> » <!before '('>
    <quibble( $¢.cursor_fresh( ::Regex ).tweak(:s))>
    <!old_rx_mods>
}

token quote:s {
    <sym> » <!before '('>
    <pat=sibble( $¢.cursor_fresh( ::Regex ), $¢.cursor_fresh( ::STD::Q ).tweak(:qq))>
    <!old_rx_mods>
}

token quote:ss {
    <sym> » <!before '('>
    <pat=sibble( $¢.cursor_fresh( ::Regex ).tweak(:s), $¢.cursor_fresh( ::STD::Q ).tweak(:qq))>
    <!old_rx_mods>
}
token quote:tr {
    <sym> » <!before '('> <pat=tribble( $¢.cursor_fresh( ::STD::Q ).tweak(:q))>
    <!old_tr_mods>
}

token old_rx_mods {
    (< i g s m x c e ] >+) 
    {{
        given $0.text {
            $_ ~~ /i/ and $¢.worryobs('/i',':i');
            $_ ~~ /g/ and $¢.worryobs('/g',':g');
            $_ ~~ /s/ and $¢.worryobs('/s','^^ and $$ anchors');
            $_ ~~ /m/ and $¢.worryobs('/m','. or \N');
            $_ ~~ /x/ and $¢.worryobs('/x','normal default whitespace');
            $_ ~~ /c/ and $¢.worryobs('/c',':c or :p');
            $_ ~~ /e/ and $¢.worryobs('/e','interpolated {...} or s{} = ... form');
            $¢.obs('suffix regex modifiers','prefix adverbs');
        }
    }}
}

token old_tr_mods {
    (< c d s ] >+) 
    {{
        given $0.text {
            $_ ~~ /c/ and $¢.worryobs('/c',':c');
            $_ ~~ /d/ and $¢.worryobs('/g',':d');
            $_ ~~ /s/ and $¢.worryobs('/s',':s');
            $¢.obs('suffix transliteration modifiers','prefix adverbs');
        }
    }}
}


token quote:quasi {
    <sym> » <!before '('> <quasiquibble($¢.cursor_fresh( ::STD::Quasi ))>
}

# XXX should eventually be derived from current Unicode tables.
constant %open2close = (
    "\x0028" => "\x0029", "\x003C" => "\x003E", "\x005B" => "\x005D",
    "\x007B" => "\x007D", "\x00AB" => "\x00BB", "\x0F3A" => "\x0F3B",
    "\x0F3C" => "\x0F3D", "\x169B" => "\x169C", "\x2039" => "\x203A",
    "\x2045" => "\x2046", "\x207D" => "\x207E", "\x208D" => "\x208E",
    "\x2208" => "\x220B", "\x2209" => "\x220C", "\x220A" => "\x220D",
    "\x2215" => "\x29F5", "\x223C" => "\x223D", "\x2243" => "\x22CD",
    "\x2252" => "\x2253", "\x2254" => "\x2255", "\x2264" => "\x2265",
    "\x2266" => "\x2267", "\x2268" => "\x2269", "\x226A" => "\x226B",
    "\x226E" => "\x226F", "\x2270" => "\x2271", "\x2272" => "\x2273",
    "\x2274" => "\x2275", "\x2276" => "\x2277", "\x2278" => "\x2279",
    "\x227A" => "\x227B", "\x227C" => "\x227D", "\x227E" => "\x227F",
    "\x2280" => "\x2281", "\x2282" => "\x2283", "\x2284" => "\x2285",
    "\x2286" => "\x2287", "\x2288" => "\x2289", "\x228A" => "\x228B",
    "\x228F" => "\x2290", "\x2291" => "\x2292", "\x2298" => "\x29B8",
    "\x22A2" => "\x22A3", "\x22A6" => "\x2ADE", "\x22A8" => "\x2AE4",
    "\x22A9" => "\x2AE3", "\x22AB" => "\x2AE5", "\x22B0" => "\x22B1",
    "\x22B2" => "\x22B3", "\x22B4" => "\x22B5", "\x22B6" => "\x22B7",
    "\x22C9" => "\x22CA", "\x22CB" => "\x22CC", "\x22D0" => "\x22D1",
    "\x22D6" => "\x22D7", "\x22D8" => "\x22D9", "\x22DA" => "\x22DB",
    "\x22DC" => "\x22DD", "\x22DE" => "\x22DF", "\x22E0" => "\x22E1",
    "\x22E2" => "\x22E3", "\x22E4" => "\x22E5", "\x22E6" => "\x22E7",
    "\x22E8" => "\x22E9", "\x22EA" => "\x22EB", "\x22EC" => "\x22ED",
    "\x22F0" => "\x22F1", "\x22F2" => "\x22FA", "\x22F3" => "\x22FB",
    "\x22F4" => "\x22FC", "\x22F6" => "\x22FD", "\x22F7" => "\x22FE",
    "\x2308" => "\x2309", "\x230A" => "\x230B", "\x2329" => "\x232A",
    "\x23B4" => "\x23B5", "\x2768" => "\x2769", "\x276A" => "\x276B",
    "\x276C" => "\x276D", "\x276E" => "\x276F", "\x2770" => "\x2771",
    "\x2772" => "\x2773", "\x2774" => "\x2775", "\x27C3" => "\x27C4",
    "\x27C5" => "\x27C6", "\x27D5" => "\x27D6", "\x27DD" => "\x27DE",
    "\x27E2" => "\x27E3", "\x27E4" => "\x27E5", "\x27E6" => "\x27E7",
    "\x27E8" => "\x27E9", "\x27EA" => "\x27EB", "\x2983" => "\x2984",
    "\x2985" => "\x2986", "\x2987" => "\x2988", "\x2989" => "\x298A",
    "\x298B" => "\x298C", "\x298D" => "\x298E", "\x298F" => "\x2990",
    "\x2991" => "\x2992", "\x2993" => "\x2994", "\x2995" => "\x2996",
    "\x2997" => "\x2998", "\x29C0" => "\x29C1", "\x29C4" => "\x29C5",
    "\x29CF" => "\x29D0", "\x29D1" => "\x29D2", "\x29D4" => "\x29D5",
    "\x29D8" => "\x29D9", "\x29DA" => "\x29DB", "\x29F8" => "\x29F9",
    "\x29FC" => "\x29FD", "\x2A2B" => "\x2A2C", "\x2A2D" => "\x2A2E",
    "\x2A34" => "\x2A35", "\x2A3C" => "\x2A3D", "\x2A64" => "\x2A65",
    "\x2A79" => "\x2A7A", "\x2A7D" => "\x2A7E", "\x2A7F" => "\x2A80",
    "\x2A81" => "\x2A82", "\x2A83" => "\x2A84", "\x2A8B" => "\x2A8C",
    "\x2A91" => "\x2A92", "\x2A93" => "\x2A94", "\x2A95" => "\x2A96",
    "\x2A97" => "\x2A98", "\x2A99" => "\x2A9A", "\x2A9B" => "\x2A9C",
    "\x2AA1" => "\x2AA2", "\x2AA6" => "\x2AA7", "\x2AA8" => "\x2AA9",
    "\x2AAA" => "\x2AAB", "\x2AAC" => "\x2AAD", "\x2AAF" => "\x2AB0",
    "\x2AB3" => "\x2AB4", "\x2ABB" => "\x2ABC", "\x2ABD" => "\x2ABE",
    "\x2ABF" => "\x2AC0", "\x2AC1" => "\x2AC2", "\x2AC3" => "\x2AC4",
    "\x2AC5" => "\x2AC6", "\x2ACD" => "\x2ACE", "\x2ACF" => "\x2AD0",
    "\x2AD1" => "\x2AD2", "\x2AD3" => "\x2AD4", "\x2AD5" => "\x2AD6",
    "\x2AEC" => "\x2AED", "\x2AF7" => "\x2AF8", "\x2AF9" => "\x2AFA",
    "\x2E02" => "\x2E03", "\x2E04" => "\x2E05", "\x2E09" => "\x2E0A",
    "\x2E0C" => "\x2E0D", "\x2E1C" => "\x2E1D", "\x3008" => "\x3009",
    "\x300A" => "\x300B", "\x300C" => "\x300D", "\x300E" => "\x300F",
    "\x3010" => "\x3011", "\x3014" => "\x3015", "\x3016" => "\x3017",
    "\x3018" => "\x3019", "\x301A" => "\x301B", "\x301D" => "\x301E",
    "\xFD3E" => "\xFD3F", "\xFE17" => "\xFE18", "\xFE35" => "\xFE36",
    "\xFE37" => "\xFE38", "\xFE39" => "\xFE3A", "\xFE3B" => "\xFE3C",
    "\xFE3D" => "\xFE3E", "\xFE3F" => "\xFE40", "\xFE41" => "\xFE42",
    "\xFE43" => "\xFE44", "\xFE47" => "\xFE48", "\xFE59" => "\xFE5A",
    "\xFE5B" => "\xFE5C", "\xFE5D" => "\xFE5E", "\xFF08" => "\xFF09",
    "\xFF1C" => "\xFF1E", "\xFF3B" => "\xFF3D", "\xFF5B" => "\xFF5D",
    "\xFF5F" => "\xFF60", "\xFF62" => "\xFF63",
);

token opener {
  <[\x0028 \x003C \x005B
    \x007B \x00AB \x0F3A
    \x0F3C \x169B \x2039
    \x2045 \x207D \x208D
    \x2208 \x2209 \x220A
    \x2215 \x223C \x2243
    \x2252 \x2254 \x2264
    \x2266 \x2268 \x226A
    \x226E \x2270 \x2272
    \x2274 \x2276 \x2278
    \x227A \x227C \x227E
    \x2280 \x2282 \x2284
    \x2286 \x2288 \x228A
    \x228F \x2291 \x2298
    \x22A2 \x22A6 \x22A8
    \x22A9 \x22AB \x22B0
    \x22B2 \x22B4 \x22B6
    \x22C9 \x22CB \x22D0
    \x22D6 \x22D8 \x22DA
    \x22DC \x22DE \x22E0
    \x22E2 \x22E4 \x22E6
    \x22E8 \x22EA \x22EC
    \x22F0 \x22F2 \x22F3
    \x22F4 \x22F6 \x22F7
    \x2308 \x230A \x2329
    \x23B4 \x2768 \x276A
    \x276C \x276E \x2770
    \x2772 \x2774 \x27C3
    \x27C5 \x27D5 \x27DD
    \x27E2 \x27E4 \x27E6
    \x27E8 \x27EA \x2983
    \x2985 \x2987 \x2989
    \x298B \x298D \x298F
    \x2991 \x2993 \x2995
    \x2997 \x29C0 \x29C4
    \x29CF \x29D1 \x29D4
    \x29D8 \x29DA \x29F8
    \x29FC \x2A2B \x2A2D
    \x2A34 \x2A3C \x2A64
    \x2A79 \x2A7D \x2A7F
    \x2A81 \x2A83 \x2A8B
    \x2A91 \x2A93 \x2A95
    \x2A97 \x2A99 \x2A9B
    \x2AA1 \x2AA6 \x2AA8
    \x2AAA \x2AAC \x2AAF
    \x2AB3 \x2ABB \x2ABD
    \x2ABF \x2AC1 \x2AC3
    \x2AC5 \x2ACD \x2ACF
    \x2AD1 \x2AD3 \x2AD5
    \x2AEC \x2AF7 \x2AF9
    \x2E02 \x2E04 \x2E09
    \x2E0C \x2E1C \x3008
    \x300A \x300C \x300E
    \x3010 \x3014 \x3016
    \x3018 \x301A \x301D
    \xFD3E \xFE17 \xFE35
    \xFE37 \xFE39 \xFE3B
    \xFE3D \xFE3F \xFE41
    \xFE43 \xFE47 \xFE59
    \xFE5B \xFE5D \xFF08
    \xFF1C \xFF3B \xFF5B
    \xFF5F \xFF62]>
}

# assumes whitespace is eaten already

method peek_delimiters {
    my $buf = self.orig;
    my $pos = self.pos;
    my $startpos = $pos;
    my $char = substr($$buf,$pos++,1);
    if $char ~~ /^\s$/ {
	self.panic("Whitespace not allowed as delimiter");
    }

# XXX not defined yet
#    <?before <+isPe> > {
#        self.panic("Use a closing delimiter for an opener is reserved");
#    }

    my $rightbrack = %open2close{$char};
    if not defined $rightbrack {
	return $char, $char;
    }
    while substr($$buf,$pos,1) eq $char {
	$pos++;
    }
    my $len = $pos - $startpos;
    my $start = $char x $len;
    my $stop = $rightbrack x $len;
    return $start, $stop;
}

role startstop[$start,$stop] {
    token starter { $start }
    token stopper { $stop }
} # end role

role stop[$stop] {
    token starter { <!> }
    token stopper { $stop }
} # end role

role unitstop[$stop] {
    token unitstopper { $stop }
} # end role

token unitstopper { $ }

method balanced ($start,$stop) { self.mixin( ::startstop[$start,$stop] ); }
method unbalanced ($stop) { self.mixin( ::stop[$stop] ); }
method unitstop ($stop) { self.mixin( ::unitstop[$stop] ); }

token codepoint {
    '[' {} ( [<!before ']'> .]*? ) ']'
}

method truly ($bool,$opt) {
    return self if $bool;
    self.panic("Can't negate $opt adverb");
}

grammar Q is STD {

    role b1 {
        token escape:sym<\\> { <sym> <item=backslash> }
        token backslash:qq { <?before 'q'> { $<quote> = $¢.cursor_fresh($+LANG).quote(); } }
        token backslash:sym<\\> { <text=sym> }
        token backslash:stopper { <text=stopper> }
        token backslash:a { <sym> }
        token backslash:b { <sym> }
        token backslash:c { <sym>
            [
            | <codepoint>
            | \d+
            | [ <[ ?.._ ]> || <.panic: "Unrecognized \\c character"> ]
            ]
        }
        token backslash:e { <sym> }
        token backslash:f { <sym> }
        token backslash:n { <sym> }
        token backslash:o { <sym> [ <octint> | '[' <octint>**',' ']' ] }
        token backslash:r { <sym> }
        token backslash:t { <sym> }
        token backslash:x { <sym> [ <hexint> | '[' [<.ws><hexint><.ws> ] ** ',' ']' ] }
        token backslash:sym<0> { <sym> }
    } # end role

    role b0 {
        token escape:sym<\\> { <!> }
    } # end role

    role c1 {
        token escape:sym<{ }> { <?before '{'> [ :lang($+LANG) <block> ] }
    } # end role

    role c0 {
        token escape:sym<{ }> { <!> }
    } # end role

    role s1 {
        token escape:sym<$> { <?before '$'> [ :lang($+LANG) <variable> <extrapost>? ] || <.panic: "Non-variable \$ must be backslashed"> }
        token special_variable:sym<$"> {
            '$' <stopper>
            <.panic: "Can't use a \$ in the last position of an interpolating string">
        }

    } # end role

    role s0 {
        token escape:sym<$> { <!> }
        token special_variable:sym<$"> { <!> }
    } # end role

    role a1 {
        token escape:sym<@> { <?before '@'> [ :lang($+LANG) <variable> <extrapost> | <!> ] } # trap ABORTBRANCH from variable's ::
    } # end role

    role a0 {
        token escape:sym<@> { <!> }
    } # end role

    role h1 {
        token escape:sym<%> { <?before '%'> [ :lang($+LANG) <variable> <extrapost> | <!> ] }
    } # end role

    role h0 {
        token escape:sym<%> { <!> }
    } # end role

    role f1 {
        token escape:sym<&> { <?before '&'> [ :lang($+LANG) <variable> <extrapost> | <!> ] }
    } # end role

    role f0 {
        token escape:sym<&> { <!> }
    } # end role

    role w1 {
        method postprocess ($s) { $s.comb }
    } # end role

    role w0 {
        method postprocess ($s) { $s }
    } # end role

    role ww1 {
        method postprocess ($s) { $s.comb }
    } # end role

    role ww0 {
        method postprocess ($s) { $s }
    } # end role

    role x1 {
        method postprocess ($s) { $s.run }
    } # end role

    role x0 {
        method postprocess ($s) { $s }
    } # end role

    role q {
        token stopper { \' }

        token escape:sym<\\> { <sym> <item=backslash> }

        token backslash:qq { <?before 'q'> { $<quote> = $¢.cursor_fresh($+LANG).quote(); } }
        token backslash:sym<\\> { <text=sym> }
        token backslash:stopper { <text=stopper> }

        # in single quotes, keep backslash on random character by default
        token backslash:misc { {} (.) { $<text> = "\\" ~ $0; } }

        # begin tweaks (DO NOT ERASE)
        multi method tweak (:single(:$q)) { self.panic("Too late for :q") }
        multi method tweak (:double(:$qq)) { self.panic("Too late for :qq") }
        # end tweaks (DO NOT ERASE)

    } # end role

    role qq does b1 does c1 does s1 does a1 does h1 does f1 {
        token stopper { \" }
        # in double quotes, omit backslash on random \W backslash by default
        token backslash:misc { {} [ (\W) { $<text> = $0.text; } | $<x>=(\w) <.panic("Unrecognized backslash sequence: '\\" ~ $<x>.text ~ "'")> ] }

        # begin tweaks (DO NOT ERASE)
        multi method tweak (:single(:$q)) { self.panic("Too late for :q") }
        multi method tweak (:double(:$qq)) { self.panic("Too late for :qq") }
        # end tweaks (DO NOT ERASE)

    } # end role

    role p5 {
        # begin tweaks (DO NOT ERASE)
        multi method tweak (:$g) { self }
        multi method tweak (:$i) { self }
        multi method tweak (:$m) { self }
        multi method tweak (:$s) { self }
        multi method tweak (:$x) { self }
        multi method tweak (:$p) { self }
        multi method tweak (:$c) { self }
        # end tweaks (DO NOT ERASE)
    } # end role

    # begin tweaks (DO NOT ERASE)

    multi method tweak (:single(:$q)) { self.truly($q,':q'); self.mixin( ::q ); }

    multi method tweak (:double(:$qq)) { self.truly($qq, ':qq'); self.mixin( ::qq ); }

    multi method tweak (:backslash(:$b))   { self.mixin($b ?? ::b1 !! ::b0) }
    multi method tweak (:scalar(:$s))      { self.mixin($s ?? ::s1 !! ::s0) }
    multi method tweak (:array(:$a))       { self.mixin($a ?? ::a1 !! ::a0) }
    multi method tweak (:hash(:$h))        { self.mixin($h ?? ::h1 !! ::h0) }
    multi method tweak (:function(:$f))    { self.mixin($f ?? ::f1 !! ::f0) }
    multi method tweak (:closure(:$c))     { self.mixin($c ?? ::c1 !! ::c0) }

    multi method tweak (:exec(:$x))        { self.mixin($x ?? ::x1 !! ::x0) }
    multi method tweak (:words(:$w))       { self.mixin($w ?? ::w1 !! ::w0) }
    multi method tweak (:quotewords(:$ww)) { self.mixin($ww ?? ::ww1 !! ::ww0) }

    multi method tweak (:heredoc(:$to)) { self.truly($to, ':to'); self.cursor_herelang; }

    multi method tweak (:$regex) {
        return ::Regex;
    }

    multi method tweak (:$trans) {
        return ::Trans;
    }

    multi method tweak (*%x) {
        my @k = keys(%x);
        self.panic("Unrecognized quote modifier: " ~ @k);
    }
    # end tweaks (DO NOT ERASE)


} # end grammar

grammar Quasi is STD {
    token term:unquote {
        <starter><starter><starter> <statementlist> <stopper><stopper><stopper>
    }

    # begin tweaks (DO NOT ERASE)
    multi method tweak (:$ast) { self; } # XXX some transformer operating on the normal AST?
    multi method tweak (:$lang) { self.cursor_fresh( $lang ); }
    multi method tweak (:$unquote) { self; } # XXX needs to override unquote
    multi method tweak (:$COMPILING) { self; } # XXX needs to lazify the lexical lookups somehow

    multi method tweak (*%x) {
        my @k = keys(%x);
        self.panic("Unrecognized quasiquote modifier: " ~ @k);
    }
    # end tweaks (DO NOT ERASE)

} # end grammar

# Note, backtracks!  So post mustn't commit to anything permanent.
regex extrapost {
    :my $inquote is context = 1;
    <post>*
    # XXX Shouldn't need a backslash on anything but the right square here
    <?after <[ \] } > ) ]> > 
}

rule multisig {
    [
	':'?'(' <in: ')', 'signature'>
    ]
    ** '|'
}

rule routine_def {
    :my $IN_DECL is context<rw> = 1;
    [ '&'<deflongname>? | <deflongname> ]? [ <multisig> | <trait> ]*
    <!{
        $¢ = $+PARSER.bless($¢);
        $IN_DECL = 0;
    }>
    <block>
}

rule method_def {
    [
    | '!'?<longname> [ <multisig> | <trait> ]*
    | <sigil> '.'
        [
        | '(' <in: ')', 'signature'>
        | '[' <in: ']', 'signature'>
        | '{' <in: '}', 'signature'>
        | <?before '<'> <postcircumfix>
        ]
        <trait>*
    ]
    <block>
}

rule regex_def {
    :my $IN_DECL is context<rw> = 1;
    [ '&'<deflongname>? | <deflongname> ]?
    [ [ ':'?'(' <signature> ')'] | <trait> ]*
    { $IN_DECL = 0; }
    <regex_block>
}

rule macro_def {
    :my $IN_DECL is context<rw> = 1;
    [ '&'<deflongname>? | <deflongname> ]? [ <multisig> | <trait> ]*
    <!{
        $¢ = $+PARSER.bless($¢);
        $IN_DECL = 0;
    }>
    <block>
}

rule trait {
    [
    | <trait_verb>
    | <trait_auxiliary>
    | <colonpair>
    ]
}

token trait_auxiliary:is {
    <sym> <.ws> <longname><postcircumfix>?
}
token trait_auxiliary:does {
    :my $PKGDECL is context = 'role';
    <sym> <.ws> <module_name>
}
token trait_auxiliary:will {
    <sym> <.ws> <identifier> <.ws> <block>
}

rule trait_verb:of      {<sym> <fulltypename> }
rule trait_verb:as      {<sym> <fulltypename> }
rule trait_verb:returns {<sym> <fulltypename> }
rule trait_verb:handles {<sym> <EXPR> }

token capterm {
    '\\'
    [
    | '(' <capture>? ')'
    | <termish>
    ]
}

rule capture {
    <EXPR>
}

token sigterm {
    ':(' <in: ')', 'signature'>
}

rule param_sep { [','|':'|';'|';;'] }

token signature {
    # XXX incorrectly scopes &infix:<x> parameters to outside following block
    :my $IN_DECL is context<rw> = 1;
    :my $zone is context<rw> = 'posreq';
    <.ws>
    [
    | <?before '-->' | ')' | '{' >
    | <parameter>
    ] ** <param_sep>
    <.ws>
    [ '-->' <.ws> <fulltypename> ]?
    { $IN_DECL = 0; }
}

rule type_declarator:subset {\
    <sym>
    <longname> { $¢.add_type($<longname>); }
    [ of <fulltypename> ]?
    where <EXPR>
}

token type_declarator:enum {
    :my $l;
    <sym> <.ws>
    [ $l = <longname> :: { $¢.add_type($l); } <.ws> ]?
    <EXPR> <.ws>
}

rule type_constraint {
    [
    | <value>
    | <fulltypename>
    | where <EXPR(item %chaining)>
    ]
}

rule post_constraint {
    [
    | <multisig>
    | where <EXPR(item %chaining)>
    ]
}

token named_param {
    :my $GOAL is context = ')';
    ':'
    [
    | <name=identifier> '(' <.ws>
	[ <named_param> | <param_var> <.ws> ]
	[ ')' || <.panic: "Unable to parse named parameter; couldn't find right parenthesis"> ]
    | <param_var>
    ]
}

token param_var {
    <sigil> <twigil>?
    [
        # Is it a longname declaration?
    || <?{ $<sigil>.text eq '&' }> <?ident> {}
        <identifier=sublongname>

    ||  # Is it a shaped array or hash declaration?
        <?{ $<sigil>.text eq '@' || $<sigil>.text eq '%' }>
        <identifier>?
        <?before <[ \< \( \[ \{ ]> >
        <postcircumfix>

        # ordinary parameter name
    || <identifier>

        # bare sigil?
    ]?
}

token parameter {
    :my $kind;

    # XXX fake out LTM till we get * working right
    <?before
        [
        | <type_constraint>
        | <param_var>
        | '*' <param_var>
        | '|' <param_var>
        | <named_param>
        ]
    >

    <type_constraint>*
    [
    | $<slurp> = [ $<quant>=[ '*' ] <param_var> ]
        { $kind = '*' }
    | $<slurp> = [ $<quant>=[ '|' ] <param_var> ]
        { $kind = '*' }
    |   [
	| <named_param> { $kind = '*'; }
        | <param_var> { $kind = '!'; }
        ]
        [ $<quant> = <[ ? ! ]> { $kind = $<quant> } ]?
    | <?> { $kind = '!' }
    ]

    <trait>*

    <post_constraint>*

    [
        <default_value> {{
            given $<quant> {
              when '!' { $¢.panic("Can't put a default on a required parameter") }
              when '*' { $¢.panic("Can't put a default on a slurpy parameter") }
            }
            $kind = '?';
        }}
    ]?

    # enforce zone constraints
    {{
        given $kind {
            when '!' {
                given $+zone {
                    when 'posopt' {
$¢.panic("Can't put required parameter after optional parameters");
                    }
                    when 'var' {
$¢.panic("Can't put required parameter after variadic parameters");
                    }
                }
            }
            when '?' {
                given $+zone {
                    when 'posreq' { $+zone = 'posopt' }
                    when 'var' {
$¢.panic("Can't put optional positional parameter after slurpy parameters");
                    }
                }
            }
            when '*' {
                $+zone = 'var';
            }
        }
    }}
}

rule default_value {
    '=' <EXPR(item %item_assignment)>
}

token statement_prefix:do      { <sym> <?before \s> <.ws> <statement> }
token statement_prefix:try     { <sym> <?before \s> <.ws> <statement> }
token statement_prefix:gather  { <sym> <?before \s> <.ws> <statement> }
token statement_prefix:contend { <sym> <?before \s> <.ws> <statement> }
token statement_prefix:async   { <sym> <?before \s> <.ws> <statement> }
token statement_prefix:lazy    { <sym> <?before \s> <.ws> <statement> }

## term

token term:sym<::?IDENT> ( --> Term) {
    $<sym> = [ '::?' <identifier> ] »
}

token term:sym<undef> ( --> Term) {
    <sym> »
    [ <?before \h*'$/' >
        <obs('$/ variable as input record separator',
             "the filehandle's .slurp method")>
    ]?
    [ <?before \h*<variable> >
        <obs('undef as a verb', 'undefine function')>
    ]?
}

token term:sym<next> ( --> Term)
    { <sym> » <.ws> [<!stdstopper> <termish>]? }

token term:sym<last> ( --> Term)
    { <sym> » <.ws> [<!stdstopper> <termish>]? }

token term:sym<redo> ( --> Term)
    { <sym> » <.ws> [<!stdstopper> <termish>]? }

token term:sym<break> ( --> Term)
    { <sym> » <.ws> [<!stdstopper> <termish>]? }

token term:sym<continue> ( --> Term)
    { <sym> » }

token term:sym<goto> ( --> Term)
    { <sym> » <.ws> <termish> }

token term:sym<self> ( --> Term)
    { <sym> » }

token term:rand ( --> Term)
    { <sym> » [ <?before \h+ [\d|'$']> <.obs('rand(N)', 'N.rand or (1..N).pick')> ]? }

token term:e ( --> Term)
    { <sym> » }

token term:i ( --> Term)
    { <sym> » }

token term:pi ( --> Term)
    { <sym> » }

token term:Inf ( --> Term)
    { <sym> » }

token term:NaN ( --> Term)
    { <sym> » }

token term:sym<*> ( --> Term)
    { <sym> }

token term:sym<**> ( --> Term)
    { <sym> }

token circumfix:sigil ( --> Term)
    { <sigil> '(' <in: ')', 'semilist', 'contextualizer'> }

#token circumfix:typecast ( --> Term)
#    { <typename> '(' <in: ')', 'semilist'> }

token circumfix:sym<( )> ( --> Term)
    { '(' <in: ')', 'semilist', 'parenthesized expression'> }

token circumfix:sym<[ ]> ( --> Term)
    { '[' <in: ']', 'semilist', 'array composer'> }

## methodcall

token infix:sym<.> ()
    { '.' <[\]\)\},:\s\$"']> <obs('. to concatenate strings', '~')> }

token postfix:sym['->'] ()
    { '->' <obs('-> to call a method', '.')> }

## autoincrement
token postfix:sym<++> ( --> Autoincrement)
    { <sym> }

token postfix:sym<--> ( --> Autoincrement)
    { <sym> }

token prefix:sym<++> ( --> Autoincrement)
    { <sym> }

token prefix:sym<--> ( --> Autoincrement)
    { <sym> }

token postfix:sym<i> ( --> Autoincrement)
    { <sym> » }

## exponentiation
token infix:sym<**> ( --> Exponentiation)
    { <sym> }

## symbolic unary
token prefix:sym<!> ( --> Symbolic_unary)
    { <sym> }

token prefix:sym<+> ( --> Symbolic_unary)
    { <sym> }

token prefix:sym<-> ( --> Symbolic_unary)
    { <sym> }

token prefix:sym<~> ( --> Symbolic_unary)
    { <sym> }

token prefix:sym<?> ( --> Symbolic_unary)
    { <sym> }

token prefix:sym<=> ( --> Symbolic_unary)
    { <sym> }

token prefix:sym<~^> ( --> Symbolic_unary)
    { <sym> }

token prefix:sym<+^> ( --> Symbolic_unary)
    { <sym> }

token prefix:sym<?^> ( --> Symbolic_unary)
    { <sym> }

token prefix:sym<^> ( --> Symbolic_unary)
    { <sym> }

token prefix:sym<|> ( --> Symbolic_unary)
    { <sym> }


## multiplicative
token infix:sym<*> ( --> Multiplicative)
    { <sym> }

token infix:sym</> ( --> Multiplicative)
    { <sym> }

token infix:sym<%> ( --> Multiplicative)
    { <sym> }

token infix:sym<+&> ( --> Multiplicative)
    { <sym> }

token infix:sym« +< » ( --> Multiplicative)
    { <sym> }

token infix:sym« << » ( --> Multiplicative)
    { <sym> <obs('<< to do left shift', '+< or ~<')> }

token infix:sym« >> » ( --> Multiplicative)
    { <sym> <obs('>> to do right shift', '+> or ~>')> }

token infix:sym« +> » ( --> Multiplicative)
    { <sym> }

token infix:sym<~&> ( --> Multiplicative)
    { <sym> }

token infix:sym<?&> ( --> Multiplicative)
    { <sym> }

token infix:sym« ~< » ( --> Multiplicative)
    { <sym> }

token infix:sym« ~> » ( --> Multiplicative)
    { <sym> }


## additive
token infix:sym<+> ( --> Additive)
    { <sym> }

token infix:sym<-> ( --> Additive)
    { <sym> }

token infix:sym<+|> ( --> Additive)
    { <sym> }

token infix:sym<+^> ( --> Additive)
    { <sym> }

token infix:sym<~|> ( --> Additive)
    { <sym> }

token infix:sym<~^> ( --> Additive)
    { <sym> }

token infix:sym<?|> ( --> Additive)
    { <sym> }

token infix:sym<?^> ( --> Additive)
    { <sym> }

## replication
# Note: no word boundary check after x, relies on longest token for x2 xx2 etc
token infix:sym<x> ( --> Replication)
    { <sym> }

token infix:sym<xx> ( --> Replication)
    { <sym> }

## concatenation
token infix:sym<~> ( --> Concatenation)
    { <sym> }


## junctive and (all)
token infix:sym<&> ( --> Junctive_and)
    { <sym> }


## junctive or (any)
token infix:sym<|> ( --> Junctive_or)
    { <sym> }

token infix:sym<^> ( --> Junctive_or)
    { <sym> }


## named unary examples
# (need \s* to win LTM battle with listops)
token prefix:sleep ( --> Named_unary)
    { <sym> » <?before \s*> }

token prefix:abs ( --> Named_unary)
    { <sym> » <?before \s*> }

token prefix:int ( --> Named_unary)
    { <sym> » <?before \s*> }

token prefix:let ( --> Named_unary)
    { <sym> » <?before \s*> }

token prefix:temp ( --> Named_unary)
    { <sym> » <?before \s*> }

## nonchaining binary
token infix:sym« <=> » ( --> Nonchaining)
    { <sym> }

token infix:cmp ( --> Nonchaining)
    { <sym> }

token infix:leg ( --> Nonchaining)
    { <sym> }

token infix:is ( --> Nonchaining)
    { <sym> }

token infix:but ( --> Nonchaining)
    { <sym> }

token infix:does ( --> Nonchaining)
    { <sym> }

token infix:sym<..> ( --> Nonchaining)
    { <sym> }

token infix:sym<^..> ( --> Nonchaining)
    { <sym> }

token infix:sym<..^> ( --> Nonchaining)
    { <sym> }

token infix:sym<^..^> ( --> Nonchaining)
    { <sym> }

token infix:sym<ff> ( --> Nonchaining)
    { <sym> }

token infix:sym<^ff> ( --> Nonchaining)
    { <sym> }

token infix:sym<ff^> ( --> Nonchaining)
    { <sym> }

token infix:sym<^ff^> ( --> Nonchaining)
    { <sym> }

token infix:sym<fff> ( --> Nonchaining)
    { <sym> }

token infix:sym<^fff> ( --> Nonchaining)
    { <sym> }

token infix:sym<fff^> ( --> Nonchaining)
    { <sym> }

token infix:sym<^fff^> ( --> Nonchaining)
    { <sym> }


## chaining binary
token infix:sym<==> ( --> Chaining)
    { <sym> }

token infix:sym<!=> ( --> Chaining)
    { <sym> }

token infix:sym« < » ( --> Chaining)
    { <sym> }

token infix:sym« <= » ( --> Chaining)
    { <sym> }

token infix:sym« > » ( --> Chaining)
    { <sym> }

token infix:sym« >= » ( --> Chaining)
    { <sym> }

token infix:sym<~~> ( --> Chaining)
    { <sym> }

token infix:sym<!~> ( --> Chaining)
    { <sym> <obs('!~ to do negated pattern matching', '!~~')> }

token infix:sym<=~> ( --> Chaining)
    { <sym> <obs('=~ to do pattern matching', '~~')> }

token infix:sym<eq> ( --> Chaining)
    { <sym> }

token infix:sym<ne> ( --> Chaining)
    { <sym> }

token infix:sym<lt> ( --> Chaining)
    { <sym> }

token infix:sym<le> ( --> Chaining)
    { <sym> }

token infix:sym<gt> ( --> Chaining)
    { <sym> }

token infix:sym<ge> ( --> Chaining)
    { <sym> }

token infix:sym<=:=> ( --> Chaining)
    { <sym> }

token infix:sym<===> ( --> Chaining)
    { <sym> }

token infix:sym<eqv> ( --> Chaining)
    { <sym> }


## tight and
token infix:sym<&&> ( --> Tight_and)
    { <sym> }


## tight or
token infix:sym<||> ( --> Tight_or)
    { <sym> }

token infix:sym<^^> ( --> Tight_or)  {
    <sym>
    { $<O><assoc> := 'list' }  # override Tight_or's 'left' associativity
}

token infix:sym<//> ( --> Tight_or)
    { <sym> }

token infix:sym<min> ( --> Tight_or)
    { <sym> }

token infix:sym<max> ( --> Tight_or)
    { <sym> }


## conditional
token infix:sym<?? !!> ( --> Conditional) {
    :my $GOAL is context = '!!';
    '??'
    <.ws>
    <EXPR(item %item_assignment)>
    [ '!!' ||
        [
        || <?before '='> <.panic: "Assignment not allowed within ??!!">
        || <?before '::'> <.panic: "Please use !! rather than ::">
        || <?before <infix>>    # Note: a tight infix would have parsed right
            <.panic: "Precedence too loose within ??!!; use ??()!! instead ">
        || <.panic: "Found ?? but no !!; possible precedence problem">
        ]
    ]
}

token infix:sym<?> ( --> Conditional)
    { <sym> <obs('?: for the conditional operator', '??!!')> }

## assignment
# There is no "--> type" because assignment may be coerced to either
# item assignment or list assignment at "make" time.

token infix:sym<=> ()
{
    <sym>
    { $¢ = (self.<sigil>//'') eq '$' 
        ?? STD::Item_assignment.coerce($¢)
        !! STD::List_assignment.coerce($¢);
    }
}

token infix:sym<:=> ( --> Item_assignment)
    { <sym> }

token infix:sym<::=> ( --> Item_assignment)
    { <sym> }

token infix:sym<.=> ( --> Item_assignment) {
    <sym> <.ws>
    [ <?before \w+';' | 'new' | 'sort' | 'subst' | 'trans' > || <worryobs('.= as append operator', '~=')> ]
    { $<O><nextterm> = 'dottyop' }
}

token infix:sym« => » ( --> Item_assignment)
    { <sym> }

# Note, other assignment ops generated by infix_postfix_meta_operator rule

## loose unary
token prefix:sym<true> ( --> Loose_unary)
    { <sym> » }

token prefix:sym<not> ( --> Loose_unary)
    { <sym> » }

## list item separator
token infix:sym<,> ( --> Comma)
    { <sym> }

token infix:sym<:> ( --> Comma)
    { <sym> }

token infix:sym« p5=> » ( --> Comma)
    { <sym> }

## list infix
token infix:sym<X> ( --> List_infix)
    { <sym> }

token infix:sym<Z> ( --> List_infix)
    { <sym> }

token infix:sym<minmax> ( --> List_infix)
    { <sym> }

token term:sym<...> ( --> List_prefix)
    { <sym> <args>? }

token term:sym<???> ( --> List_prefix)
    { <sym> <args>? }

token term:sym<!!!> ( --> List_prefix)
    { <sym> <args>? }

token term:sigil ( --> List_prefix)
{
    <sigil> <?before \s> <arglist>
    { $<sym> = $<sigil>.item; }
}

# token term:typecast ( --> List_prefix)
#     { <typename> <?spacey> <arglist> { $<sym> = $<typename>.item; } }

# force identifier(), identifier.(), etc. to be a function call always
token term:identifier ( --> Term )
{
    :my $i;
    $i = <identifier> <args( $¢.is_type($i.text) )>
    {{ %ROUTINES{$i.text} ~= $¢.lineof($¢.pos) ~ ' ' }}
}

token term:opfunc ( --> Term )
{
    <category> <colonpair>+ <args>
}

token args ($istype = 0) {
    :my $listopy = 0;
    [
    | '.(' <in: ')', 'semilist', 'argument list'> {*}             #= func args
    | '(' <in: ')', 'semilist', 'argument list'> {*}              #= func args
    | <.unsp> '.'? '(' <in: ')', 'semilist', 'argument list'> {*} #= func args
    | {} [<?before \s> <!{ $istype }> <.ws> <!infixstopper> <arglist>]? { $listopy = 1 }
    ]

    [
    || <?{ $listopy }>
    || ':' <?before \s> <arglist>    # either switch to listopiness
    || {{ $+prevop = $<O> = {}; }}   # or allow adverbs (XXX needs hoisting?)
    ]
}

# names containing :: may or may not be function calls
# bare identifier without parens also handled here if no other rule parses it
token term:name ( --> Term)
{
    <longname>
    [
    ||  <?{
            $¢.is_type($<longname>.text) or substr($<longname>.text,0,2) eq '::'
        }>
        # parametric type?
        <.unsp>? [ <?before '['> <postcircumfix> ]?
        [
            '::'
            <?before [ '«' | '<' | '{' | '<<' ] > <postcircumfix>
            {*}                                                 #= packagevar 
        ]?
        {*}                                                     #= typename

    # unrecognized names are assumed to be post-declared listops.
    || <args>?
    ]
}

## loose and
token infix:sym<and> ( --> Loose_and)
    { <sym> }

token infix:sym<andthen> ( --> Loose_and)
    { <sym> }

token infix:sym<andthen> ( --> Loose_and)
    { <sym> }

## loose or
token infix:sym<or> ( --> Loose_or)
    { <sym> }

token infix:sym<orelse> ( --> Loose_or)
    { <sym> }

token infix:sym<xor> ( --> Loose_or)
    { <sym> }

token infix:sym<orelse> ( --> Loose_or)
     { <sym> }

token infix:sym<;> ( --> Sequencer)
    { <sym> }

token infix:sym« <== » ( --> Sequencer)
    { <sym> }

token infix:sym« ==> » ( --> Sequencer)
    { <sym> {*} }              #'

token infix:sym« <<== » ( --> Sequencer)
    { <sym> }

token infix:sym« ==>> » ( --> Sequencer)
    { <sym> {*} }              #'

## expression terminator

token terminator:sym<;> ( --> Terminator)
    { <?before ';' > }

token terminator:sym<if> ( --> Terminator)
    { <?before 'if' » > }

token terminator:sym<unless> ( --> Terminator)
    { <?before 'unless' » > }

token terminator:sym<while> ( --> Terminator)
    { <?before 'while' » > }

token terminator:sym<until> ( --> Terminator)
    { <?before 'until' » > }

token terminator:sym<for> ( --> Terminator)
    { <?before 'for' » > }

token terminator:sym<given> ( --> Terminator)
    { <?before 'given' » > }

token terminator:sym<when> ( --> Terminator)
    { <?before 'when' » > }

token terminator:sym« --> » ( --> Terminator)
    { <?before '-->' > {*} }              #'

token terminator:sym<)> ( --> Terminator)
    { <?before <sym> > }

token terminator:sym<]> ( --> Terminator)
    { <?before ']' > }

token terminator:sym<}> ( --> Terminator)
    { <?before '}' > }

token terminator:sym<!!> ( --> Terminator)
    { <?before '!!' > <?{ $+GOAL eq '!!' }> }

regex infixstopper {
    | <?before <stopper> >
    | <?before '!!' > <?{ $+GOAL eq '!!' }>
    | <?before '{' | <lambda> > <?{ $+GOAL eq '{' and $¢.<_>[$¢.pos]<ws> }>
}

# overridden in subgrammars
token stopper { <!> }

# hopefully we can include these tokens in any outer LTM matcher
regex stdstopper {
    :my @stub = return self if self.<_>[self.pos].:exists<endstmt>;
    [
    | <?terminator>
    | <?unitstopper>
    | $					# unlikely, check last (normal LTM behavior)
    ]
    { $¢.<_>[$¢.pos]<endstmt> ||= 1; }
}

# A fairly complete operator precedence parser

method EXPR ($preclvl)
{
    temp $CTX = self.callm if $*DEBUG +& DEBUG::trace_call;
    if self.peek {
        return self._AUTOLEXpeek('EXPR', $retree);
    }
    my $preclim = $preclvl ?? $preclvl.<prec> // $LOOSEST !! $LOOSEST;
    my $inquote is context = 0;
    my $prevop is context<rw>;
    my @termstack;
    my @opstack;
    my $termish = 'termish';

    push @opstack, { 'O' => item %terminator, 'sym' => '' };         # (just a sentinel value)

    my $here = self;
    self.deb("In EXPR, at ", $here.pos) if $*DEBUG +& DEBUG::EXPR;

    my &reduce := -> {
        self.deb("entering reduce, termstack == ", +@termstack, " opstack == ", +@opstack) if $*DEBUG +& DEBUG::EXPR;
        my $op = pop @opstack;
        given $op<O><assoc> // 'unary' {
            when 'chain' {
                self.deb("reducing chain") if $*DEBUG +& DEBUG::EXPR;
                my @chain;
                push @chain, pop(@termstack);
                push @chain, $op;
                while @opstack {
                    last if $op<O><prec> ne @opstack[*-1]<O><prec>;
                    push @chain, pop(@termstack).cleanup;
                    push @chain, pop(@opstack);
                }
                push @chain, pop(@termstack).cleanup;
                @chain = reverse @chain if @chain > 1;
                $op<O><chain> = [@chain];
                push @termstack, $op;
            }
            when 'list' {
                self.deb("reducing list") if $*DEBUG +& DEBUG::EXPR;
                my @list;
                push @list, pop(@termstack);
		my $s = $op<sym>;
                while @opstack {
                    self.deb($s ~ " vs " ~ @opstack[*-1]<sym>) if $*DEBUG +& DEBUG::EXPR;
                    last if $s ne @opstack[*-1]<sym>;
		    if @termstack and defined @termstack[0] {
			push @list, pop(@termstack).cleanup;
		    }
		    else {
			self.worry("Missing term in " ~ $s ~ " list");
		    }
                    pop(@opstack);
                }
		if @termstack and defined @termstack[0] {
		    push @list, pop(@termstack).cleanup;
		}
		elsif $s ne ',' {
		    self.worry("Missing final term in '" ~ $s ~ "' list");
		}
                @list = reverse @list if @list > 1;
                $op<list> = [@list];
                push @termstack, $op;
            }
            when 'unary' {
                self.deb("reducing") if $*DEBUG +& DEBUG::EXPR;
                my @list;
                self.deb("Termstack size: ", +@termstack) if $*DEBUG +& DEBUG::EXPR;

                self.deb($op.dump) if $*DEBUG +& DEBUG::EXPR;
		$op<arg> = (pop @termstack).cleanup;
		$op<_from> = $op<arg><_from>
		    if $op<_from> > $op<arg><_from>;
		$op<_to> = $op<arg><_to>
		    if $op<_to> < $op<arg><_to>;

                push @termstack, $op;
            }
            default {
                self.deb("reducing") if $*DEBUG +& DEBUG::EXPR;
                my @list;
                self.deb("Termstack size: ", +@termstack) if $*DEBUG +& DEBUG::EXPR;

                self.deb($op.dump) if $*DEBUG +& DEBUG::EXPR;
		$op<right> = (pop @termstack).cleanup;
		$op<left> = (pop @termstack).cleanup;
		$op<_from> = $op<left><_from>;
		$op<_to> = $op<right><_to>;

                push @termstack, $op;
            }
        }
    };

    loop {
        self.deb("In loop, at ", $here.pos) if $*DEBUG +& DEBUG::EXPR;
        my $oldpos = $here.pos;
        my @t = $here.$termish;       # presumed to eat trailing ws too

        if not @t or not $here = @t[0] or ($here.pos == $oldpos and $termish eq 'termish') {
            return ();
            # $here.panic("Failed to parse a required term");
        }
        $termish = 'termish';

        # interleave prefix and postfix, pretend they're infixish
        my $M = $here;
        my @pre;
        @pre = @($M<pre>) if $M<pre>;
        my @post;
        @post = @($M<post>) if $M<post>;
        loop {
            if @pre {
                if @post and @post[0]<O><prec> gt @pre[0]<O><prec> {
                    push @opstack, shift @post;
                }
                else {
                    push @opstack, pop @pre;
                }
            }
            elsif @post {
                push @opstack, shift @post;
            }
            else {
                last;
            }
        }

        push @termstack, $here;
        self.deb("after push: " ~ (0+@termstack)) if $*DEBUG +& DEBUG::EXPR;
        $oldpos = $here.pos;
        my @infix = $here.cursor_fresh.infixish();
        last unless @infix;
        my $infix = @infix[0];
        last unless $infix.pos > $oldpos;
        
        # XXX might want to allow this in a declaration though
        if not $infix { $here.panic("Can't have two terms in a row") }

        if not $infix<sym> {
            die $infix.dump if $*DEBUG +& DEBUG::EXPR;
        }

        my $inO = $infix<O>;
        $prevop = $inO;
        my Str $inprec = $inO<prec>;
        if not defined $inprec {
            self.deb("No prec given in infix!") if $*DEBUG +& DEBUG::EXPR;
            die $infix.dump if $*DEBUG +& DEBUG::EXPR;
            $inprec = %terminator<prec>;
        }

        last unless $inprec gt $preclim;

        $here = $infix.cursor_fresh.ws();


        # substitute precedence for listops
        $inO<prec> = $inO<sub> if $inO<sub>;

        # Does new infix (or terminator) force any reductions?
        while @opstack[*-1]<O><prec> gt $inprec {
            reduce();
        }

        # Not much point in reducing the sentinels...
        last if $inprec lt $LOOSEST;

        # Equal precedence, so use associativity to decide.
        if @opstack[*-1]<O><prec> eq $inprec {
            given $inO<assoc> {
                when 'non'   { $here.panic("\"$infix\" is not associative") }
                when 'left'  { reduce() }   # reduce immediately
                when 'right' { }            # just shift
                when 'chain' { }            # just shift
                when 'list'  {              # if op differs reduce else shift
                    reduce() if $infix<sym> !eqv @opstack[*-1]<sym>;
                }
                default { $here.panic("Unknown associativity \"$_\" for \"$infix\"") }
            }
        }
        $termish = $inO<nextterm> if $inO<nextterm>;
        push @opstack, $infix;
    }
    reduce() while +@termstack > 1;
    if @termstack {
        +@termstack == 1 or $here.panic("Internal operator parser error, termstack == " ~ (+@termstack));
        @termstack[0]<_from> = self.pos;
        @termstack[0]<_to> = $here.pos;
    }
    @termstack;
}

#################################################
## Regex
#################################################

grammar Regex is STD {

    # begin tweaks (DO NOT ERASE)
    multi method tweak (:Perl5(:$P5)) { self.cursor_fresh( ::STD::Q ).mixin( ::q ).mixin( ::p5 ) }
    multi method tweak (:overlap(:$ov)) { self }
    multi method tweak (:exhaustive(:$ex)) { self }
    multi method tweak (:continue(:$c)) { self }
    multi method tweak (:pos(:$p)) { self }
    multi method tweak (:sigspace(:$s)) { self }
    multi method tweak (:ratchet(:$r)) { self }
    multi method tweak (:global(:$g)) { self }
    multi method tweak (:ignorecase(:$i)) { self }
    multi method tweak (:ignoreaccent(:$a)) { self }
    multi method tweak (:samecase(:$ii)) { self }
    multi method tweak (:sameaccent(:$aa)) { self }
    multi method tweak (:$nth) { self }
    multi method tweak (:st(:$nd)) { self }
    multi method tweak (:rd(:$th)) { self }
    multi method tweak (:$x) { self }
    multi method tweak (:$bytes) { self }
    multi method tweak (:$codes) { self }
    multi method tweak (:$graphs) { self }
    multi method tweak (:$chars) { self }
    multi method tweak (:$rw) { self.panic(":rw not implemented") }
    multi method tweak (:$keepall) { self.panic(":keepall not implemented") }
    multi method tweak (:$panic) { self.panic(":panic not implemented") }
    # end tweaks (DO NOT ERASE)

    token category:metachar { <sym> }
    proto token metachar { <...> }

    token category:backslash { <sym> }
    proto token backslash { <...> }

    token category:assertion { <sym> }
    proto token assertion { <...> }

    token category:quantifier { <sym> }
    proto token quantifier { <...> }

    token category:mod_internal { <sym> }
    proto token mod_internal { <...> }

    proto token rxinfix { <...> }

    token ws {
        <?{ $+sigspace }>
	|| [ <?before \s | '#'> <nextsame> ]?   # still get all the pod goodness, hopefully
    }

    token sigspace {
	<?before \s | '#'> [ :lang($¢.cursor_fresh($+LANG)) <.ws> ]
    }

    # suppress fancy end-of-line checking
    token codeblock {
        :my $GOAL is context = '}';
        '{' :: [ :lang($¢.cursor_fresh($+LANG)) <statementlist> ]
        [ '}' || <.panic: "Unable to parse statement list; couldn't find right brace"> ]
    }

    rule nibbler {
        :my $sigspace    is context<rw> = $+sigspace    // 0;
        :my $ratchet     is context<rw> = $+ratchet     // 0;
        :my $ignorecase is context<rw> = $+ignorecase // 0;
        :my $ignoreaccent    is context<rw> = $+ignoreaccent    // 0;
        [ \s* < || | && & > ]?
        <EXPR>
    }

    token termish {
	<.ws>
        <quantified_atom>+
    }
    token infixish {
        <!infixstopper>
        <!stdstopper>
        <rxinfix>
        {
            $<O> = $<rxinfix><O>;
            $<sym> = $<rxinfix><sym>;
        }
    }

    token rxinfix:sym<||> ( --> Tight_or ) { <sym> }
    token rxinfix:sym<&&> ( --> Tight_and ) { <sym> }
    token rxinfix:sym<|> ( --> Junctive_or ) { <sym> }
    token rxinfix:sym<&> ( --> Junctive_and ) { <sym> }

    token quantified_atom {
        <!stopper>
        <!rxinfix>
        <atom>
        [ <.ws> <quantifier>
#            <?{ $<atom>.max_width }>
#                || <.panic: "Can't quantify zero-width atom">
        ]?
	<.ws>
    }

    token atom {
        [
        | \w
        | <metachar> ::
        | <.panic: "Unrecognized regex metacharacter">
        ]
    }

    # sequence stoppers
    token metachar:sym« > » { '>'  :: <fail> }
    token metachar:sym<&&>  { '&&' :: <fail> }
    token metachar:sym<&>   { '&'  :: <fail> }
    token metachar:sym<||>  { '||' :: <fail> }
    token metachar:sym<|>   { '|'  :: <fail> }
    token metachar:sym<]>   { ']'  :: <fail> }
    token metachar:sym<)>   { ')'  :: <fail> }

    token metachar:quant { <quantifier> <.panic: "quantifier quantifies nothing"> }

    # "normal" metachars

    token metachar:sigwhite {
	<sigspace>
    }

    token metachar:sym<{ }> {
        <?before '{'>
        <codeblock>
        {{ $/<sym> := <{ }> }}
    }

    token metachar:mod {
        <mod_internal>
        { $/<sym> := $<mod_internal><sym> }
    }

    token metachar:sym<:> {
        <sym>
    }

    token metachar:sym<::> {
        <sym>
    }

    token metachar:sym<:::> {
        <sym>
    }

    token metachar:sym<[ ]> {
        '[' {} [:lang(self.unbalanced(']')) <nibbler>]
        [ ']' || <.panic: "Unable to parse regex; couldn't find right bracket"> ]
        { $/<sym> := <[ ]> }
    }

    token metachar:sym<( )> {
        '(' {} [:lang(self.unbalanced(')')) <nibbler>]
        [ ')' || <.panic: "Unable to parse regex; couldn't find right parenthesis"> ]
        { $/<sym> := <( )> }
    }

    token metachar:sym« <( » { '<(' }
    token metachar:sym« )> » { ')>' }

    token metachar:sym« << » { '<<' }
    token metachar:sym« >> » { '>>' }
    token metachar:sym< « > { '«' }
    token metachar:sym< » > { '»' }

    token metachar:qw {
        <?before '<' \s >  # (note required whitespace)
        <quote>
    }

    token metachar:sym«< >» {
        '<' <unsp>? {} <assertion>
        [ '>' || <.panic: "regex assertion not terminated by angle bracket"> ]
    }

    token metachar:sym<\\> { <sym> <backslash> }
    token metachar:sym<.>  { <sym> }
    token metachar:sym<^^> { <sym> }
    token metachar:sym<^>  { <sym> }
    token metachar:sym<$$> {
        <sym>
        [ (\w+) <obs("\$\$" ~ $0.text ~ " to deref var inside a regex", "\$(\$" ~ $0.text ~ ")")> ]?
    }
    token metachar:sym<$>  {
        '$'
        <?before
        | \s
        | '|'
        | '&'
        | ')'
        | ']'
        | '>'
        | $
	| <stopper>
        >
    }

    token metachar:sym<' '> { <?before "'"> [:lang($¢.cursor_fresh($+LANG)) <quote>] }
    token metachar:sym<" "> { <?before '"'> [:lang($¢.cursor_fresh($+LANG)) <quote>] }

    token metachar:var {
        <!before '$$'>
        <?before <sigil>>
        [:lang($¢.cursor_fresh($+LANG)) <variable>]
        <.ws>
        $<binding> = ( '=' <.ws> <quantified_atom> )?
        { $<sym> = $<variable>.item; }
    }

    token backslash:unspace { <?before \s> <.SUPER::ws> }

    token backslash:a { :i <sym> }
    token backslash:b { :i <sym> }
    token backslash:c { :i <sym>
        [
        | <codepoint>
        | \d+
        | [ <[ ?.._ ]> || <.panic: "Unrecognized \\c character"> ]
        ]
    }
    token backslash:d { :i <sym> }
    token backslash:e { :i <sym> }
    token backslash:f { :i <sym> }
    token backslash:h { :i <sym> }
    token backslash:n { :i <sym> }
    token backslash:o { :i <sym> [ <octint> | '['<octint>[','<octint>]*']' ] }
    token backslash:r { :i <sym> }
    token backslash:s { :i <sym> }
    token backslash:t { :i <sym> }
    token backslash:v { :i <sym> }
    token backslash:w { :i <sym> }
    token backslash:x { :i <sym> [ <hexint> | '[' [<.ws><hexint><.ws> ] ** ',' ']' ] }
    token backslash:misc { $<litchar>=(\W) }
    token backslash:oops { <.panic: "Unrecognized regex backslash sequence"> }

    token assertion:sym<...> { <sym> }
    token assertion:sym<???> { <sym> }
    token assertion:sym<!!!> { <sym> }

    token assertion:sym<?> { <sym> [ <?before '>'> | <assertion> ] }
    token assertion:sym<!> { <sym> [ <?before '>'> | <assertion> ] }
    token assertion:sym<*> { <sym> [ <?before '>'> | <.ws> <nibbler> ] }

    token assertion:sym<{ }> { <codeblock> }

    token assertion:variable {
        <?before <sigil>>  # note: semantics must be determined per-sigil
        [:lang($¢.cursor_fresh($+LANG).unbalanced('>')) <variable=EXPR(item %LOOSEST)>]
    }

    token assertion:method {
        '.' [
            | <?before <alpha> > <assertion>
            | [ :lang($¢.cursor_fresh($+LANG).unbalanced('>')) <dottyop> ]
            ]
    }

    token assertion:identifier { <identifier> [               # is qq right here?
                                    | <?before '>' >
                                    | <.ws> <nibbler>
                                    | '=' <assertion>
                                    | ':' <.ws>
                                        [ :lang($¢.cursor_fresh($+LANG).unbalanced('>')) <arglist> ]
                                    | '(' {}
					[ :lang($¢.cursor_fresh($+LANG)) <arglist> ]
					[ ')' || <.panic: "Assertion call missing right parenthesis"> ]
                                    ]?
    }

    # stupid special case
    token assertion:name { <?before \w*'::('> [ :lang($¢.cursor_fresh($+LANG).unbalanced('>')) <name> ]
                                    [
                                    | <?before '>' >
                                    | <.ws> <nibbler>
                                    | '=' <assertion>
                                    | ':' <.ws>
                                        [ :lang($¢.cursor_fresh($+LANG).unbalanced('>')) <arglist> ]
                                    | '(' {}
					[ :lang($¢.cursor_fresh($+LANG)) <arglist> ]
					[ ')' || <.panic: "Assertion call missing right parenthesis"> ]
                                    ]?
    }

    token assertion:sym<[> { <before '[' > <cclass_elem>+ }
    token assertion:sym<+> { <before '+' > <cclass_elem>+ }
    token assertion:sym<-> { <before '-' > <cclass_elem>+ }
    token assertion:sym<.> { <sym> }
    token assertion:sym<,> { <sym> }
    token assertion:sym<~~> { <sym> [ <?before '>'> | \d+ | <desigilname> ] }

    token assertion:bogus { <.panic: "Unrecognized regex assertion"> }

    token cclass_elem {
        [ '+' | '-' ]?
        [
        | <name>
        | <before '['> <quibble($¢.cursor_fresh( ::STD::Q ).tweak(:q))> # XXX parse as q[] for now
        ]
    }

    token mod_arg { '(' <in: ')', 'semilist', 'modifier argument'> }

    token mod_internal:sym<:my>    { ':' <?before 'my' \s > [:lang($¢.cursor_fresh($+LANG)) <statement> <eat_terminator> ] }

    token mod_internal:sym<:i>    { $<sym>=[':i'|':ignorecase'] » { $+ignorecase = 1 } }
    token mod_internal:sym<:!i>   { $<sym>=[':i'|':ignorecase'] » { $+ignorecase = 0 } }
    # XXX will this please work somehow ???
    token mod_internal:sym<:i( )> { $<sym>=[':i'|':ignorecase'] <mod_arg> { $+ignorecase = $<mod_arg>.eval } }

    token mod_internal:sym<:a>    { $<sym>=[':a'|':ignoreaccent'] » { $+ignoreaccent = 1 } }
    token mod_internal:sym<:!a>   { $<sym>=[':a'|':ignoreaccent'] » { $+ignoreaccent = 0 } }
    # XXX will this please work somehow ???
    token mod_internal:sym<:a( )> { $<sym>=[':a'|':ignoreaccent'] <mod_arg> { $+ignoreaccent = $<mod_arg>.eval } }

    token mod_internal:sym<:s>    { ':s' 'igspace'? » { $+sigspace = 1 } }
    token mod_internal:sym<:!s>   { ':s' 'igspace'? » { $+sigspace = 0 } }
    token mod_internal:sym<:s( )> { ':s' 'igspace'? <mod_arg> { $+sigspace = $<mod_arg>.eval } }

    token mod_internal:sym<:r>    { ':r' 'atchet'? » { $+ratchet = 1 } }
    token mod_internal:sym<:!r>   { ':r' 'atchet'? » { $+ratchet = 0 } }
    token mod_internal:sym<:r( )> { ':r' 'atchet'? » <mod_arg> { $+ratchet = $<mod_arg>.eval } }

    token mod_internal:adv {
        <?before ':' <identifier> > [ :lang($¢.cursor_fresh($+LANG)) <quotepair> ] { $/<sym> := «: $<quotepair><key>» }
    }

    token mod_internal:oops { ':' <.panic: "Unrecognized regex modifier"> }

    token quantifier:sym<*>  { <sym> <quantmod> }
    token quantifier:sym<+>  { <sym> <quantmod> }
    token quantifier:sym<?>  { <sym> <quantmod> }
    token quantifier:sym<**> { <sym> :: <sigspace>? <quantmod> <sigspace>?
        [
        | \d+ [ '..' [ \d+ | '*' ] ]?
        | <codeblock>
        | <quantified_atom>
        ]
    }

    token quantifier:sym<~~> {
        [
        | '!' <sym>
        | <sym>
        ]
        <sigspace> <quantified_atom> }

    token quantmod { [ '?' | '!' | ':' | '+' ]? }

} # end grammar

# The <panic: "message"> rule is called for syntax errors.
# If there are any <suppose> points, backtrack and retry parse
# with a different supposition.  If it gets farther than the
# panic point, print out the supposition ("Looks like you
# used a Perl5-style shift operator (<<) at line 42.  Maybe
# you wanted +< or |< instead.")  Or some such...
# In any event, this is only for better diagnostics, and
# further compilation is suppressed by the <commit><fail>.

# token panic (Str $s) { <commit> <fail($s)> }

method panic (Str $s) {
    my $m;
    my $here = self;

    # Have we backed off recently?
    my $highvalid = self.pos <= $*HIGHWATER;

    $here = self.cursor($*HIGHWATER) if $highvalid;

    my $first = $here.lineof($COMPILING::LAST_NIBBLE.<firstpos>);
    my $last = $here.lineof($COMPILING::LAST_NIBBLE.<lastpos>);
    if $here.lineof($here.pos) == $last and $first != $last {
        $m ~= "\n(Possible runaway string from line $first)";
    }
    else {
        $first = $here.lineof($COMPILING::LAST_NIBBLE_MULTILINE.<firstpos>);
        $last = $here.lineof($COMPILING::LAST_NIBBLE_MULTILINE.<lastpos>);
        # the bigger the string (in lines), the further back we suspect it
        if $here.lineof($here.pos) - $last < $last - $first  {
            $m ~= "\n(Possible runaway string from line $first to line $last)";
        }
    }

    $m ~= "\n" ~ $s;

    if $highvalid {
        $m ~= $*HIGHMESS if $*HIGHMESS;
        $*HIGHMESS = $m;
    }
    else {
        # not in backoff, so at "bleeding edge", as it were... therefore probably
        # the exception will be caught and re-panicked later, so remember message
        $*HIGHMESS ~= "\n" ~ $s;
    }

    $m ~= $here.locmess;

    if $highvalid and %$*HIGHEXPECT {
        my @keys = sort keys %$*HIGHEXPECT;
        if @keys > 1 {
            $m ~= "\n    expecting any of:\n\t" ~ join("\n\t", sort keys %$*HIGHEXPECT);
        }
        else {
            $m ~= "\n    expecting @keys";
        }
    }

    if @COMPILING::WORRIES {
        $m ~= "\nOther potential difficulties:\n  " ~ join( "\n  ", @COMPILING::WORRIES);
    }

    die "############# PARSE FAILED #############" ~ $m ~ "\n";
}

method worry (Str $s) {
    push @COMPILING::WORRIES, $s ~ self.locmess;
}

method locmess () {
    my $orig = self.orig;
    my $text = $$orig;
    my $pre = substr($text, 0, self.pos);
    my $line = self.lineof(self.pos);
    $pre = substr($pre, -40, 40);
    1 while $pre ~~ s!.*\n!!;
    my $post = substr($text, self.pos, 40);
    1 while $post ~~ s!(\n.*)!!;
    " at " ~ $COMPILING::FILE ~ " line $line:\n------> " ~ $Cursor::GREEN ~ $pre ~ $Cursor::RED ~ 
        "$post$Cursor::CLEAR";
}

method lineof ($p) {
    return 1 unless defined $p;
    my $posprops = self.<_>;
    my $line = $posprops.[$p]<L>;
    return $line if $line;
    $line = 1;
    my $pos = 0;
    my $orig = self.orig;
    my @text = split(/^/,$$orig);
    for @text {
        $posprops.[$pos++]<L> = $line
            for 1 .. chars($_);
        $line++;
    }
    return $posprops.[$p]<L> // 0;
}

# not quite a "between" combinator...
token in (Str $stop, Str $insides, Str $name = $insides) {
    :my $GOAL is context = $stop;
    <x=$insides> $stop {{ $/.{$insides} = $<x>; $/.:delete<x> }} || <.panic: "Unable to parse $name; couldn't find final '$stop'">
}

# "when" arg assumes more things will become obsolete after Perl 6 comes out...
method obs (Str $old, Str $new, Str $when = ' in Perl 6') {
    self.panic("Obsolete use of $old;$when please use $new instead");
}

method worryobs (Str $old, Str $new, Str $when = ' in Perl 6') {
    self.worry("Possible obsolete use of $old;$when please use $new instead");
    self;
}

## vim: expandtab sw=4 syntax=perl6
