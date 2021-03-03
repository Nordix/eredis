.PHONY: all compile clean test ut ct-tcp ct-tls edoc xref dialyzer elvis cover coverview

REDIS_VERSION ?= 6.0.10

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

# Generate and patch documentation.
# The patching is needed to be able to generate documentation via Elixirs mix.
# Following changes are needed:
# - Handle link targets in headers, changes:
#     '### <a name="link">Header</a> ###' to
#     '<a name="link"></a> ### Header ###'
# - Newline needed for before following tags:
#     </table> </dd> </pre>
# - Removal of unneeded line breaks (visual only)
#
# Note: sed on macOS requires explicit in-place extensions (-i <extension>)
edoc:
	@rebar3 edoc skip_deps=true
	for file in doc/*.md ; do \
		sed -i.bak 's|### <a name="\(.*\)">\(.*\)</a> ###|<a name="\1"></a>\n### \2 ###|g' $${file} ; \
		sed -i.bak 's|</table>|\n</table>|g' $${file} ; \
		sed -i.bak 's|</dd>|\n</dd>|g' $${file} ; \
		sed -i.bak 's|</code></pre>|</code>\n</pre>|g' $${file} ; \
		sed -i.bak 's|<br />||g' $${file} ; \
		rm $${file}.bak ; \
	done

publish: edoc
	@touch doc/.build # Prohibit ex_doc to remove .md files
	@mix docs
	@if [ ! -z "$$(git status --untracked-file=no --porcelain)" ]; \
	then \
		echo "Error: Working directory is dirty. Please commit before publish!"; \
		exit 1; \
	fi
	mix hex.publish

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
