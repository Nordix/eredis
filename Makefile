.PHONY: all compile clean test doc xref dialyzer elvis cover

REDIS_VERSION ?= 6.0.1

all: compile xref dialyzer elvis

compile:
	@rebar3 compile

clean:
	@rebar3 clean
	@rm -rf _build

test:
	-@docker rm -f redis
	@docker run --name redis -d --net=host -v $(shell pwd)/test/configs:/conf:ro \
		redis:$(REDIS_VERSION) redis-server /conf/redis.conf
	@rebar3 eunit -v --cover
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
