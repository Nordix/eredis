.PHONY: all compile clean test doc xref dialyzer elvis cover

REDIS_VERSION ?= 6.0.1

all: compile xref dialyzer elvis

compile:
	@rebar3 compile

clean:
	@rebar3 clean
	@rm -rf _build

test: test-tls test-tcp

test-tcp:
	-@docker rm -f redis
	@docker run --name redis -d --net=host redis:$(REDIS_VERSION)
	@rebar3 eunit -v --cover_export_name tcp \
		--suite eredis_parser_tests,eredis_sub_tests,eredis_tests || \
		{ docker logs redis; exit 1; }
	@docker rm -f redis

test-tls:
	-@docker rm -f redis
	@docker run --name redis -d --net=host -v $(shell pwd)/priv/configs:/conf:ro \
		redis:$(REDIS_VERSION) redis-server /conf/redis_tls.conf
	@rebar3 eunit -v --cover_export_name tls \
		--suite eredis_tls_tests || { docker logs redis; exit 1; }
	@docker rm -f redis

edoc:
	@rebar3 edoc skip_deps=true

xref:
	@rebar3 xref

dialyzer:
	@rebar3 dialyzer

elvis:
	@elvis rock

cover:
	@rebar3 cover -v

coveralls:
	@rebar3 coveralls send

coverview: cover
	xdg-open _build/test/cover/index.html
