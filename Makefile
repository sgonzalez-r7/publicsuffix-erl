all: ebin/tld.beam

ebin/tld.beam: src/tld.erl
	erlc -o ebin src/tld.erl

src/tld.erl: ebin/tld_generator.beam
	erl -pa ebin -noshell -eval 'tld_generator:generate(file, "publicsuffix.dat"), halt()' > src/tld.erl
	# erl -pa ebin -noshell -eval 'tld_generator:generate()' > src/tld.erl

ebin/tld_generator.beam: src/tld_generator.erl
	erlc -o ebin src/tld_generator.erl

test: compile
	mkdir -p .eunit
	erlc -o .eunit src/tld.erl tests/tld_tests.erl
	erl +pc unicode -noshell -pa .eunit -eval "eunit:test(tld, [verbose])" -s init stop
