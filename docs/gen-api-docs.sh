#!/bin/sh
# Regenerates API.md.
#
# The prose for every function comes from libpq.sgml -- the source of the
# libpq chapter of the PostgreSQL manual -- so the reference always describes
# the PostgreSQL version this binding is built against, with no network
# access and no chance of version skew.
#
# Four inputs:
#
#   libpq.sgml                descriptions and C signatures. The makefile
#                             passes its path as LIBPQ_SGML: the vendored
#                             source tree has it, and a PG_SYSTEM=1 build
#                             fetches the one file for the version it linked.
#
#   userfunctions.c           the AddUDF calls. Everything the CLIPS side
#                             contributes rides along with the registration:
#
#                               /* doc-group: <title> */     starts a group,
#                                   matching a "## <title>" heading in the
#                                   template
#                               /* doc: <args> -> <kind> */  trails one AddUDF:
#                                   the argument names in call order, "?" for
#                                   optional, and the kind of value the
#                                   handler returns (handle, boolean, integer,
#                                   float, string, symbol, multifield, fact or
#                                   instance)
#
#   docs/api-template.md      everything that is not a function entry; each
#                             "<!-- functions -->" marker is replaced by the
#                             entries of the group it sits in
#
#   docs/api-overrides.md     replaces the manual wording for the functions
#                             whose CLIPS calling convention differs from C,
#                             and supplies the description for the functions
#                             that have no C counterpart at all
#
# A registration without a doc annotation is an error: adding a UDF without
# documenting it should not pass silently. Nor should a libpq function nobody
# has decided about: every function libpq.sgml documents must either be bound
# to a UDF or named under "## Not exposed" in the template, where the reason
# it is left out is written down. Both are checked at the end.
#
# Cross-references become links into the online manual. An id libpq.sgml
# defines is resolved through the section that contains it, which is how the
# chunked HTML is laid out; an id from another chapter is assumed to name a
# top-level section, which is its own page. The referenced ids that are
# neither are listed in xref_page() below, and a guc-* reference becomes the
# name of the setting rather than a link.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

# The makefile passes both; the defaults are for running this by hand.
sgml=${LIBPQ_SGML:-}
if [ -z "$sgml" ]; then
	for candidate in "$root"/vendor/postgresql-*/doc/src/sgml/libpq.sgml \
	                 "$root"/vendor/doc/libpq-*.sgml; do
		[ -f "$candidate" ] && sgml=$candidate
	done
fi

version=${PG_VERSION:-}
if [ -z "$version" ]; then
	version=$(printf '%s\n' "$sgml" | tr '/' '\n' | \
	          sed -n 's/^postgresql-\([0-9.]*\)$/\1/p; s/^libpq-\([0-9.]*\)\.sgml$/\1/p' | \
	          head -1)
fi
major=${version%%.*}

sources=$root/userfunctions.c
overrides=$root/docs/api-overrides.md
template=$root/docs/api-template.md
out=${1:-$root/API.md}

for f in "$sgml" "$sources" "$overrides" "$template"; do
	[ -f "$f" ] || { echo "gen-api-docs: missing input: $f" >&2; exit 1; }
done

[ -n "$version" ] || { echo "gen-api-docs: cannot tell which PostgreSQL version $sgml is for; pass PG_VERSION" >&2; exit 1; }

tmp=$out.tmp.$$
trap 'rm -f "$tmp"' EXIT INT TERM

awk -v pg_version="$version" -v pg_major="$major" \
    -v sources="$sources" -v sgml="$sgml" -v overrides="$overrides" \
    -v template="$template" '
# ===========================================================================
# Helpers
# ===========================================================================
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function squeeze(s) { gsub(/[ \t\n]+/, " ", s); return trim(s) }

# The key both sides of the name mapping are looked up by: PQexecParams and
# pq-exec-params are the same function, and nothing else about how they are
# spelled has to agree.
function squash(s) {
	s = tolower(s)
	gsub(/[-_]/, "", s)
	return s
}

function die(msg) {
	print "gen-api-docs: " msg > "/dev/stderr"
	errors++
}

# ---------------------------------------------------------------------------
# The CLIPS types a restriction string declares, as the reference spells them
# ---------------------------------------------------------------------------
function type_names(letters,   i, c, out, name) {
	out = ""
	for (i = 1; i <= length(letters); i++) {
		c = substr(letters, i, 1)
		name = ""
		if (c == "e") name = "EXTERNAL-ADDRESS"
		else if (c == "s") name = "STRING"
		else if (c == "y") name = "SYMBOL"
		else if (c == "l") name = "INTEGER"
		else if (c == "d") name = "FLOAT"
		else if (c == "b") name = "BOOLEAN"
		else if (c == "m") name = "MULTIFIELD"
		else if (c == "f") name = "FACT-ADDRESS"
		else if (c == "i") name = "INSTANCE-ADDRESS"
		else if (c == "n") name = "INSTANCE-NAME"
		else if (c == "*") name = "any"
		if (name == "") continue
		out = out (out == "" ? "" : "/") "`" name "`"
	}
	return out
}

function return_type(kind) {
	if (kind == "handle")     return "`EXTERNAL-ADDRESS`"
	if (kind == "boolean")    return "`BOOLEAN`"
	if (kind == "integer")    return "`INTEGER`"
	if (kind == "float")      return "`FLOAT`"
	if (kind == "string")     return "`STRING`"
	if (kind == "symbol")     return "`SYMBOL`"
	if (kind == "multifield") return "`MULTIFIELD`"
	if (kind == "fact")       return "`FACT-ADDRESS`"
	if (kind == "instance")   return "`INSTANCE-ADDRESS`"
	return "`" toupper(kind) "`"
}

# ===========================================================================
# Pass 1: userfunctions.c -- what is bound, in the order it is registered
# ===========================================================================
FILENAME == sources {
	# A registration inside "#if CLIPSPG_HAVE_nn" is compiled in only where
	# the libpq being built against has the function, so the entry has to
	# say so.
	if (match($0, /^#if CLIPSPG_HAVE_[0-9]+/)) {
		since = substr($0, RSTART + 17, RLENGTH - 17)
		next
	}
	if ($0 ~ /^#endif/) { since = ""; next }

	if (match($0, /\/\* doc-group:[^*]*\*\//)) {
		group = substr($0, RSTART, RLENGTH)
		sub(/^\/\* doc-group:[ \t]*/, "", group)
		sub(/[ \t]*\*\/$/, "", group)
		current_group = trim(group)
		group_order[++group_count] = current_group
		next
	}

	if ($0 !~ /AddUDF\(env,"/) next

	line = $0
	doc = ""
	if (match(line, /\/\* doc:[^*]*\*\//)) {
		doc = substr(line, RSTART, RLENGTH)
		sub(/^\/\* doc:[ \t]*/, "", doc)
		sub(/[ \t]*\*\/$/, "", doc)
		doc = trim(doc)
		line = substr(line, 1, RSTART - 1)
	}

	n = split(line, q, "\"")
	name = q[2]
	returns = q[4]

	# The restriction string is the next quoted argument unless the call
	# passes NULL for it, which is how a function with no arguments is
	# registered.
	restriction = (q[5] ~ /NULL/) ? "" : q[6]

	split(q[5], counts, ",")
	minargs = counts[2] + 0
	maxargs = counts[3] + 0

	if (name == "") { die("could not read a function name out of: " $0); next }
	if (doc == "")  { die(name " has no doc annotation on its AddUDF") ; next }
	if (current_group == "") { die(name " is registered before any doc-group") ; next }

	udf_order[++udf_count] = name
	udf_since[name] = since
	if (since != "") since_count[since]++
	udf_group[name] = current_group
	udf_returns[name] = returns
	udf_restriction[name] = restriction
	udf_min[name] = minargs
	udf_max[name] = maxargs
	bound[squash(name)] = name
	group_members[current_group] = group_members[current_group] " " name

	# doc: <arg> <arg>? ... -> <kind>
	split(doc, halves, "->")
	udf_kind[name] = trim(halves[2])
	args = trim(halves[1])
	split(restriction, restrictions, ";")
	udf_argc[name] = split(args, arglist, /[ \t]+/)
	if (args == "") udf_argc[name] = 0
	for (i = 1; i <= udf_argc[name]; i++) {
		argname = arglist[i]
		optional = (argname ~ /\?$/)
		sub(/\?$/, "", argname)
		udf_arg[name, i] = argname
		udf_arg_optional[name, i] = optional
		udf_arg_types[name, i] = type_names(restrictions[i + 1])
	}
	if (udf_argc[name] != maxargs)
		die(name " is registered for " maxargs " arguments and documents " udf_argc[name])
	next
}

# ===========================================================================
# Pass 2: libpq.sgml -- the manual for the version being built against
#
# Two things are collected: where every id lives, which is what makes a
# cross-reference into a link, and the raw block of every varlistentry whose
# term is a function, which is what the entries are rendered from.
# ===========================================================================
FILENAME == sgml {
	line = $0

	rest = line
	while (match(rest, /PQ[A-Za-z0-9_]+/)) {
		mentioned[substr(rest, RSTART, RLENGTH)] = 1
		rest = substr(rest, RSTART + RLENGTH)
	}

	if (match(line, /<sect1 id="[^"]*"/)) {
		cursect1 = substr(line, RSTART + 11, RLENGTH - 12)
		idsect[cursect1] = cursect1
		lastid = cursect1
	}
	else if (match(line, /<sect[23] id="[^"]*"/)) {
		id = substr(line, RSTART + 11, RLENGTH - 12)
		idsect[id] = cursect1
		lastid = id
	}
	else if (match(line, /id="[^"]*"/)) {
		id = substr(line, RSTART + 4, RLENGTH - 5)
		if (!(id in idsect)) idsect[id] = cursect1
		lastid = id
	}

	if (lastid != "" && match(line, /<title>[^<]*<\/title>/)) {
		title = substr(line, RSTART + 7, RLENGTH - 15)
		if (!(lastid in idtitle)) idtitle[lastid] = trim(title)
	}

	# The block of one function entry. Nested variablelists are part of the
	# entry that contains them, so what is tracked is the depth rather than
	# the next closing tag.
	opens = gsub(/<varlistentry/, "<varlistentry", line)
	closes = gsub(/<\/varlistentry>/, "</varlistentry>", line)

	if (entry_depth == 0 && opens > 0) {
		entry_depth = opens - closes
		entry_lines = 0
		entry_name_count = 0
		entry_seen_listitem = 0
		in_entry_term = 0
		entry_raw[++entry_lines] = line
		if (entry_depth <= 0) entry_depth = 0
		next
	}

	if (entry_depth > 0) {
		entry_raw[++entry_lines] = line

		# One entry can document several functions -- PQresetStart and
		# PQresetPoll share one -- and a <term> can run over several lines,
		# so the names are collected from every term before the entry
		# body starts rather than from the line the term opens on.
		if (!entry_seen_listitem) {
			if (line ~ /<term[ >]/) in_entry_term = 1
			if (in_entry_term) {
				termrest = line
				while (match(termrest, /<function>[A-Za-z0-9_]+<\/function>/)) {
					candidate = substr(termrest, RSTART + 10, RLENGTH - 21)
					termrest = substr(termrest, RSTART + RLENGTH)
					if (candidate ~ /^PQ/) entry_names[++entry_name_count] = candidate
				}
			}
			if (line ~ /<\/term>/) in_entry_term = 0
			if (line ~ /<listitem>/) entry_seen_listitem = 1
		}

		entry_depth += opens - closes
		if (entry_depth <= 0) {
			entry_depth = 0
			for (k = 1; k <= entry_name_count; k++) {
				entry_name = entry_names[k]
				if (squash(entry_name) in documented) continue
				documented[squash(entry_name)] = entry_name
				doc_order[++doc_count] = entry_name
				block_lines[entry_name] = entry_lines
				for (i = 1; i <= entry_lines; i++)
					block[entry_name, i] = entry_raw[i]
			}
		}
		next
	}
	next
}

# ===========================================================================
# Pass 3: docs/api-overrides.md -- what the manual does not say, because it
# is about C and this is not
# ===========================================================================
FILENAME == overrides {
	if ($0 ~ /^### /) {
		name = $0
		sub(/^### /, "", name)
		gsub(/`/, "", name)
		override_name = trim(name)
		override_section = "description"
		next
	}
	if (override_name == "") next
	if ($0 ~ /^#### Arguments/) { override_section = "arguments"; next }
	if ($0 ~ /^#### Returns/)   { override_section = "returns"; next }

	if (override_section == "description") {
		if (trim($0) == "" && override_description[override_name] == "") next
		override_description[override_name] = override_description[override_name] $0 "\n"
	}
	else if (override_section == "arguments") {
		if (match($0, /^- `[^`]+`:/)) {
			argname = substr($0, 4, RLENGTH - 5)
			sub(/^- `/, "", argname)
			sub(/`:$/, "", argname)
			text = substr($0, RSTART + RLENGTH)
			override_argument[override_name, trim(argname)] = trim(text)
		}
	}
	else if (override_section == "returns") {
		if (trim($0) == "" && override_returns[override_name] == "") next
		override_returns[override_name] = override_returns[override_name] $0 "\n"
	}
	next
}

# ===========================================================================
# Cross-references
# ===========================================================================

# The page an id from another chapter lives on, for the handful of referenced
# ids that are not top-level sections. Everything else in another chapter is
# one, and is its own page.
function xref_page(id) {
	if (id ~ /^protocol-flow-/)                   return "protocol-flow"
	if (id == "ssl-certificate-creation")         return "ssl-tcp"
	if (id == "ddl-schemas-patterns")             return "ddl-schemas"
	if (id == "configure-option-with-libcurl")    return "install-make"
	if (id ~ /^postgres-fdw-options/)             return "postgres-fdw"
	return ""
}

# A libpq function is named the way a CLIPS program would call it wherever
# this binding calls it, and by its C name where it does not.
function function_name(pqname) {
	if (squash(pqname) in bound) return bound[squash(pqname)]
	return pqname
}

function xref_url(id,   page) {
	if (id in idsect) {
		if (idsect[id] == id) return docs_base "/" id ".html"
		return docs_base "/" idsect[id] ".html#" toupper(id)
	}
	page = xref_page(id)
	if (page != "") return docs_base "/" page ".html#" toupper(id)
	return docs_base "/" id ".html"
}

# What the manual would print in place of an <xref>: the title of what is
# being pointed at. For a target in another chapter there is no title to
# read, so the id is turned back into the words it was made from.
function xref_label(id,   label) {
	if (id in idtitle) return idtitle[id]
	if (id ~ /^sql-/) { label = substr(id, 5); return toupper(label) }
	label = id
	gsub(/-/, " ", label)
	return label
}

# ===========================================================================
# Inline markup
# ===========================================================================
function inline(s,   id, label, url, before, after, tag, text, clips) {
	gsub(/&mdash;/, "\342\200\224", s)
	gsub(/&nbsp;/, " ", s)
	gsub(/&lt;/, "<", s)
	gsub(/&gt;/, ">", s)
	gsub(/&amp;/, "\\&", s)
	gsub(/&copy;/, "(c)", s)

	# <xref linkend="x"/>, which has no text of its own
	while (match(s, /<xref[ \t]+linkend="[^"]*"[^>]*\/>/)) {
		tag = substr(s, RSTART, RLENGTH)
		before = substr(s, 1, RSTART - 1)
		after = substr(s, RSTART + RLENGTH)
		match(tag, /linkend="[^"]*"/)
		id = substr(tag, RSTART + 9, RLENGTH - 10)
		if (id ~ /^guc-/) {
			label = substr(id, 5)
			s = before "`" label "`" after
		}
		else if (id ~ /^libpq-PQ/) {
			s = before "`" function_name(substr(id, 7)) "`" after
		}
		else {
			s = before "[" xref_label(id) "](" xref_url(id) ")" after
		}
	}

	# <link linkend="x">text</link>
	while (match(s, /<link[ \t]+linkend="[^"]*"[^>]*>/)) {
		tag = substr(s, RSTART, RLENGTH)
		before = substr(s, 1, RSTART - 1)
		after = substr(s, RSTART + RLENGTH)
		match(tag, /linkend="[^"]*"/)
		id = substr(tag, RSTART + 9, RLENGTH - 10)
		if (match(after, /<\/link>/)) {
			text = substr(after, 1, RSTART - 1)
			after = substr(after, RSTART + RLENGTH)
			if (id ~ /^guc-/)          s = before "`" text "`" after
			else if (id ~ /^libpq-PQ/) s = before "`" function_name(substr(id, 7)) "`" after
			else                       s = before "[" text "](" xref_url(id) ")" after
		}
		else {
			s = before after
		}
	}
	gsub(/<\/?link[^>]*>/, "", s)

	# Function names, which are what most of this prose is about: the ones
	# bound here are named the way a CLIPS program would call them.
	while (match(s, /<function>[A-Za-z0-9_]+<\/function>/)) {
		tag = substr(s, RSTART, RLENGTH)
		before = substr(s, 1, RSTART - 1)
		after = substr(s, RSTART + RLENGTH)
		text = substr(tag, 11, length(tag) - 21)
		clips = (squash(text) in bound) ? bound[squash(text)] : text
		s = before "`" clips "`" after
	}
	gsub(/<\/?function[^>]*>/, "`", s)

	# Everything else that names something the reader would type
	gsub(/<\/?literal[^>]*>/, "`", s)
	gsub(/<\/?symbol[^>]*>/, "`", s)
	gsub(/<\/?parameter[^>]*>/, "`", s)
	gsub(/<\/?varname[^>]*>/, "`", s)
	gsub(/<\/?structname[^>]*>/, "`", s)
	gsub(/<\/?structfield[^>]*>/, "`", s)
	gsub(/<\/?type[^>]*>/, "`", s)
	gsub(/<\/?envar[^>]*>/, "`", s)
	gsub(/<\/?option[^>]*>/, "`", s)
	gsub(/<\/?filename[^>]*>/, "`", s)
	gsub(/<\/?command[^>]*>/, "`", s)
	gsub(/<\/?returnvalue[^>]*>/, "`", s)
	gsub(/<\/?replaceable[^>]*>/, "`", s)
	gsub(/<\/?emphasis[^>]*>/, "*", s)

	# Tags that are only saying what kind of word this is
	gsub(/<\/?acronym[^>]*>/, "", s)
	gsub(/<\/?productname[^>]*>/, "", s)
	gsub(/<\/?application[^>]*>/, "", s)
	gsub(/<\/?firstterm[^>]*>/, "", s)
	gsub(/<\/?quote[^>]*>/, "\"", s)

	# Anything left is markup this reference has no use for.
	gsub(/<[^>]*>/, "", s)

	# The manual says what the C function returns, and these wrappers do not
	# return what it returns: a call that worked answers TRUE and one that
	# did not answers FALSE. The functions where the mapping is not that
	# simple -- where zero means "not yet" rather than "no" -- say so in
	# their own words, from the overrides.
	gsub(/Returns 1/, "Answers `TRUE`", s)
	gsub(/Returns 0/, "Answers `FALSE`", s)
	gsub(/returns 1/, "answers `TRUE`", s)
	gsub(/return 1 /, "answer `TRUE` ", s)
	gsub(/returns 0/, "answers `FALSE`", s)
	gsub(/return 0 /, "answer `FALSE` ", s)
	gsub(/returns a nonzero value/, "answers `TRUE`", s)
	gsub(/returns nonzero/, "answers `TRUE`", s)
	gsub(/returns a null pointer/, "answers `FALSE`", s)
	gsub(/returns NULL/, "answers `FALSE`", s)
	gsub(/a null pointer/, "`FALSE`", s)

	# A code span inside a code span leaves two backticks together, which is
	# one code span with the inner tags gone -- which is what was wanted.
	while (sub(/``/, "`", s)) { }

	return squeeze(s)
}

# ===========================================================================
# Rendering one entry from its SGML
#
# The block is walked once, tag by tag. Everything that is not a tag is text
# for the paragraph being built; a block-level tag ends that paragraph and
# says what the next one is -- a bullet, a term, a line of a table, a quoted
# note.
# ===========================================================================

function emit(text) { OUT = OUT text }

# A synopsis is code, so it is kept as it was written -- but the manual marks
# up the parameter names inside it, and that markup is not code.
function verbatim_clean(line) {
	gsub(/<[^>]*>/, "", line)
	gsub(/&lt;/, "<", line)
	gsub(/&gt;/, ">", line)
	gsub(/&amp;/, "\&", line)
	return line
}

function indent_for(depth,   i, s) {
	s = ""
	for (i = 1; i < depth; i++) s = s "  "
	return s
}

function flush_text(text,   marker, n, before) {
	while (match(text, /\001[0-9]+\002/)) {
		marker = substr(text, RSTART + 1, RLENGTH - 2) + 0
		before = substr(text, 1, RSTART - 1)
		text = substr(text, RSTART + RLENGTH)
		flush_para(before)
		flush_verbatim(marker)
	}
	flush_para(text)
}

function flush_para(text,   prefix, body) {
	text = inline(text)
	if (text == "") return

	prefix = ""
	if (list_depth > 0) {
		if (item_pending) {
			prefix = indent_for(list_depth) "- "
			if (term_text != "") {
				text = "**" inline(term_text) "**: " text
				term_text = ""
			}
			item_pending = 0
		}
		else prefix = indent_for(list_depth) "  "
	}
	if (quote_depth > 0) prefix = "> " prefix

	emit(prefix text "\n\n")
}

function flush_verbatim(marker,   i, prefix, lang) {
	prefix = (list_depth > 0) ? indent_for(list_depth) "  " : ""
	if (quote_depth > 0) prefix = "> " prefix
	lang = verbatim_lang[marker]
	emit(prefix "```" lang "\n")
	for (i = 1; i <= verbatim_lines[marker]; i++)
		emit(prefix verbatim_clean(verbatim[marker, i]) "\n")
	emit(prefix "```\n\n")
}

# The first pass over the block: verbatim blocks are lifted out whole, and
# everything else becomes one long line with the tags still in it.
function collect_flow(name,   i, line, flow, inverb, marker, text) {
	flow = ""
	inverb = 0
	first_synopsis = ""
	for (i = 1; i <= block_lines[name]; i++) {
		line = block[name, i]

		if (inverb) {
			if (line ~ /<\/(synopsis|programlisting)>/) {
				sub(/<\/(synopsis|programlisting)>.*$/, "", line)
				if (trim(line) != "") {
					verbatim[marker, ++verbatim_lines[marker]] = line
					if (first_synopsis_pending) first_synopsis = first_synopsis line "\n"
				}
				inverb = 0
				if (first_synopsis_pending) { first_synopsis_pending = 0; verbatim_lines[marker] = 0; marker_dropped = 1 }
				continue
			}
			verbatim[marker, ++verbatim_lines[marker]] = line
			if (first_synopsis_pending) first_synopsis = first_synopsis line "\n"
			continue
		}

		if (match(line, /<(synopsis|programlisting)[^>]*>/)) {
			text = substr(line, 1, RSTART - 1)
			flow = flow " " text
			marker = ++verbatim_count
			verbatim_lines[marker] = 0
			verbatim_lang[marker] = (substr(line, RSTART + 1, 8) == "synopsis") ? "c" : ""
			# The first synopsis of an entry is the C prototype, which the
			# entry prints in a place of its own rather than in the middle
			# of the prose.
			if (first_synopsis == "" && verbatim_lang[marker] == "c") first_synopsis_pending = 1
			else flow = flow " \001" marker "\002"
			line = substr(line, RSTART + RLENGTH)
			if (line ~ /<\/(synopsis|programlisting)>/) {
				sub(/<\/(synopsis|programlisting)>.*$/, "", line)
				if (trim(line) != "") verbatim[marker, ++verbatim_lines[marker]] = line
				if (first_synopsis_pending) {
					first_synopsis = line "\n"
					first_synopsis_pending = 0
					verbatim_lines[marker] = 0
				}
				continue
			}
			inverb = 1
			continue
		}

		flow = flow " " line
	}
	return flow
}

function render_block(name,   flow, rest, tag, text, tagname) {
	OUT = ""
	list_depth = 0
	quote_depth = 0
	item_pending = 0
	term_text = ""
	in_term = 0
	skip_depth = 0
	in_table = 0
	row_text = ""
	BUF = ""

	first_synopsis = ""
	first_synopsis_pending = 0
	rest = collect_flow(name, "")

	# The indexterms are the manual index, not the documentation.
	gsub(/<indexterm>.*<\/indexterm>/, "", rest)
	gsub(/<indexterm[^>]*>/, "", rest)
	gsub(/<\/indexterm>/, "", rest)
	gsub(/<primary>[^<]*<\/primary>/, "", rest)
	gsub(/<secondary>[^<]*<\/secondary>/, "", rest)

	outer_terms_done = 0

	while (match(rest, /<\/?(para|itemizedlist|orderedlist|variablelist|simplelist|listitem|varlistentry|term|note|warning|caution|tip|important|table|informaltable|tgroup|thead|tbody|row|entry|title|footnote|member|colspec)[^>]*>/)) {
		text = substr(rest, 1, RSTART - 1)
		tag = substr(rest, RSTART, RLENGTH)
		rest = substr(rest, RSTART + RLENGTH)

		if (skip_depth > 0) {
			tagname = tag
			sub(/^<\/?/, "", tagname); sub(/[ >].*$/, "", tagname); sub(/>$/, "", tagname)
			if (tagname == skip_tag) {
				if (tag ~ /^<\//) skip_depth--
				else skip_depth++
			}
			continue
		}

		BUF = BUF text

		if (tag ~ /^<\/para>/ || tag ~ /^<\/member>/) { flush_text(BUF); BUF = "" }
		else if (tag ~ /^<para/ || tag ~ /^<member/) { flush_text(BUF); BUF = "" }
		else if (tag ~ /^<(itemizedlist|orderedlist|variablelist|simplelist)/) {
			flush_text(BUF); BUF = ""
			list_depth++
		}
		else if (tag ~ /^<\/(itemizedlist|orderedlist|variablelist|simplelist)/) {
			flush_text(BUF); BUF = ""
			list_depth--
			if (list_depth < 0) list_depth = 0
		}
		else if (tag ~ /^<listitem/) {
			flush_text(BUF); BUF = ""
			outer_terms_done = 1
			item_pending = 1
		}
		else if (tag ~ /^<\/listitem/) { flush_text(BUF); BUF = ""; item_pending = 0 }
		else if (tag ~ /^<term/) {
			flush_text(BUF); BUF = ""
			in_term = 1
		}
		else if (tag ~ /^<\/term/) {
			# The terms of the entry itself are the names of the functions
			# it documents, which the heading has already said.
			if (!outer_terms_done) BUF = ""
			else { term_text = BUF }
			BUF = ""
			in_term = 0
		}
		else if (tag ~ /^<(note|warning|caution|tip|important)/) {
			flush_text(BUF); BUF = ""
			quote_depth++
			emit("> **" (tag ~ /warning|caution/ ? "Warning" : (tag ~ /important/ ? "Important" : (tag ~ /tip/ ? "Tip" : "Note"))) "**\n>\n")
		}
		else if (tag ~ /^<\/(note|warning|caution|tip|important)/) {
			flush_text(BUF); BUF = ""
			quote_depth--
			if (quote_depth < 0) quote_depth = 0
		}
		else if (tag ~ /^<(table|informaltable)/) { flush_text(BUF); BUF = ""; in_table++ }
		else if (tag ~ /^<\/(table|informaltable)/) { BUF = ""; in_table--; if (in_table < 0) in_table = 0 }
		else if (tag ~ /^<thead/) { skip_tag = "thead"; skip_depth = 1; BUF = "" }
		else if (tag ~ /^<row/) { row_text = ""; BUF = "" }
		else if (tag ~ /^<\/entry/) {
			if (in_table) {
				row_text = row_text (row_text == "" ? "" : " \342\200\224 ") inline(BUF)
				BUF = ""
			}
		}
		else if (tag ~ /^<\/row/) {
			if (in_table && trim(row_text) != "") emit("- " row_text "\n")
			row_text = ""
			BUF = ""
		}
		else if (tag ~ /^<title/) { skip_tag = "title"; skip_depth = 1; BUF = "" }
		else if (tag ~ /^<footnote/) { skip_tag = "footnote"; skip_depth = 1; BUF = "" }
		else { BUF = "" }
	}

	flush_text(BUF BUF_REST)
	BUF = ""

	# A table run of bullets ends without a blank line after it.
	if (OUT !~ /\n\n$/) OUT = OUT "\n"
	return OUT
}

# ===========================================================================
# One entry of the reference
# ===========================================================================
function call_form(name,   i, s) {
	s = "(" name
	for (i = 1; i <= udf_argc[name]; i++) {
		if (udf_arg_optional[name, i])
			s = s " [?" udf_arg[name, i] "]"
		else
			s = s " ?" udf_arg[name, i]
	}
	return s ")"
}

function print_entry(name,   i, description, csig, text, argname, line) {
	printf "### `%s`\n\n", name

	printf "```clips\n%s\n```\n\n", call_form(name)

	if (name in override_description && trim(override_description[name]) != "") {
		description = override_description[name]
		csig = ""
		if (squash(name) in documented) {
			render_block(documented[squash(name)])
			csig = first_synopsis
		}
	}
	else if (squash(name) in documented) {
		description = render_block(documented[squash(name)])
		csig = first_synopsis
	}
	else {
		die(name " has neither an entry in the manual nor a description in the overrides")
		description = ""
		csig = ""
	}

	printf "%s", description
	if (description !~ /\n\n$/) printf "\n"

	if (udf_since[name] != "") {
		printf "**Requires PostgreSQL %s or later.** Built against an older libpq, this function is not defined at all; `pq-built-version` is how a program asks.\n\n", udf_since[name]
	}

	if (trim(csig) != "") {
		printf "In C:\n\n```c\n%s```\n\n", verbatim_clean(csig)
	}

	if (udf_argc[name] > 0) {
		printf "#### Arguments\n\n"
		for (i = 1; i <= udf_argc[name]; i++) {
			argname = udf_arg[name, i]
			line = "- " udf_arg_types[name, i] " `" argname "`"
			if (udf_arg_optional[name, i]) line = line " (optional)"
			if ((name SUBSEP argname) in override_argument)
				line = line ": " override_argument[name, argname]
			printf "%s\n\n", line
		}
	}

	printf "#### Returns\n\n"
	if (name in override_returns && trim(override_returns[name]) != "") {
		text = override_returns[name]
		sub(/\n+$/, "", text)
		printf "%s\n\n", text
	}
	else {
		printf "- %s\n\n", return_type(udf_kind[name])
	}
}

function print_group(name,   i, members, count, member) {
	count = split(trim(group_members[name]), members, /[ \t]+/)
	if (count == 0) die("the template asks for the entries of \"" name "\", and nothing is registered in it")
	for (i = 1; i <= count; i++) print_entry(members[i])
}

# ===========================================================================
# Pass 4: docs/api-template.md -- everything that is not an entry
# ===========================================================================
FILENAME == template {
	line = $0

	if (line ~ /^## /) {
		heading = line
		sub(/^## /, "", heading)
		template_group = trim(heading)
		template_group_seen[template_group] = 1
		in_not_exposed = (template_group == "Not exposed")
	}

	# A bullet there names the functions first and the reason after " -- ",
	# so only the first half is a list of names -- and a bullet may run over
	# several lines before it gets to the reason.
	if (in_not_exposed && line ~ /^- /) in_names = 1
	if (in_not_exposed && in_names) {
		rest = line
		if (sub(/ -- .*$/, "", rest)) in_names = 0
		if (line !~ /^[- ]/) { rest = ""; in_names = 0 }
		while (match(rest, /PQ[A-Za-z0-9_]+/)) {
			not_exposed[substr(rest, RSTART, RLENGTH)] = 1
			rest = substr(rest, RSTART + RLENGTH)
		}
	}

	if (line ~ /<!-- functions -->/) {
		print_group(template_group)
		next
	}

	gsub(/@PG_VERSION@/, pg_version, line)
	gsub(/@PG_MAJOR@/, pg_major, line)
	gsub(/@BOUND@/, udf_count, line)
	gsub(/@DOCUMENTED@/, doc_count, line)
	gsub(/@SINCE16@/, since_count["16"] + 0, line)
	gsub(/@SINCE17@/, since_count["17"] + 0, line)
	gsub(/@SINCE18@/, since_count["18"] + 0, line)
	gsub(/@ALWAYS@/, udf_count - (since_count["16"] + since_count["17"] + since_count["18"]), line)
	gsub(/@DOCS_BASE@/, docs_base, line)
	print line
	next
}

BEGIN {
	docs_base = "https://www.postgresql.org/docs/" pg_major
	errors = 0
}

# ===========================================================================
# The audit
#
# Every function the manual documents has to have been decided about, and
# every registration has to be documented. Neither is something to discover
# later from a reader.
# ===========================================================================
END {
	for (i = 1; i <= doc_count; i++) {
		name = doc_order[i]
		if (squash(name) in bound) continue
		if (name in not_exposed) continue
		die(name " is documented by libpq " pg_version " and is neither bound nor named under \"## Not exposed\"")
	}

	for (name in not_exposed) {
		if (squash(name) in bound)
			die(name " is named under \"## Not exposed\" and is also bound to " bound[squash(name)])
		else if (!(name in mentioned))
			die(name " is named under \"## Not exposed\" and is not a function libpq " pg_version " has")
	}

	for (i = 1; i <= group_count; i++) {
		if (!(group_order[i] in template_group_seen))
			die("userfunctions.c has a doc-group \"" group_order[i] "\" that the template has no heading for")
	}

	if (errors > 0) {
		print "gen-api-docs: " errors " problem(s); API.md was not written" > "/dev/stderr"
		exit 1
	}
}
' "$sources" "$sgml" "$overrides" "$template" > "$tmp"

mv "$tmp" "$out"
echo "gen-api-docs: wrote $out from libpq $version"
