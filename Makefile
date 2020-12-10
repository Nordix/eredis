.PHONY: all compile clean test ut ct-tcp ct-tls edoc xref dialyzer elvis cover coverview

REDIS_VERSION ?= 6.0.4

all: compile xref dialyzer elvis

compile:
	@rebar3 compile

clean:
	@rebar3 clean
	@rm -rf _build

test: ut ct

ut:
	@rebar3 eunit -v --cover_export_name ut

ct: ct-tcp ct-tls

ct-tcp:
	-@docker rm -f redis
	@docker run --name redis -d --net=host redis:$(REDIS_VERSION)
	@rebar3 ct -v --cover_export_name ct-tcp \
		--suite eredis_tcp_SUITE,eredis_pubsub_SUITE || { docker logs redis; exit 1; }
	@docker rm -f redis

ct-tls:
	@priv/update-client-cert.sh tls_soon_expired_client_certs
	-@docker rm -f redis
	@docker run --name redis -d --net=host -v $(shell pwd)/priv/configs:/conf:ro \
		redis:$(REDIS_VERSION) redis-server /conf/redis_tls.conf
	@rebar3 ct -v --cover_export_name ct-tls \
		--suite eredis_tls_SUITE || { docker logs redis; exit 1; }
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

coverview: cover
	xdg-open _build/test/cover/index.html
