.PHONY: build clean install

build:
	shards install
	crystal build src/calendar.cr -o bin/calendar --release

clean:
	rm -rf bin/ lib/ .shards/

install: build
	install -D bin/calendar /usr/local/bin/calendar
