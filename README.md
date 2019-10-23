# Hockey Scraper

A hockey scraper written in Julia, based on [Harry Shormer's Python scraper](https://github.com/HarryShomer/Hockey-Scraper).

## Getting Started

### Prerequisites

While installing the package should automatically install all dependencies, we note them here in case you would like to install manually.

* Cascadia - CSS Selector library for HTML scraping "54eefc05-d75b-58de-a785-1a3403f0919f"
* DataFrames - DataFrame Library
* Gumbo - HTML Scraping Library
* HTTP - To make HTTP requests
* JSON - JSON Parsing Library
* LightXML - XML Parsing Library

### Installing

For all games after 2011, the `master` branch can be used. For games prior to that, please refer to the `html-pbp-scraper` branch.

```julia
] # to launch Pkg manager
add "https://github.com/mikeroher/Hockey.jl"
```

### Running

To use the module, we expose a single function that returns the play by play and optionally the player shift data.

```julia
# By default, we don't retreive shifts as there's an optional parameter to indicate if you want to scrape shifts
Hockey.scrape_game(game_id, scrape_shifts::Bool=false) 
```

## Contributing

Please read [CONTRIBUTING.md](https://gist.github.com/PurpleBooth/b24679402957c63ec426) for details on our code of conduct, and the process for submitting pull requests to us.

## License

This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details

## Acknowledgments

* [Harry Shormer's NHL and NWHL Scraper written in Python](https://github.com/HarryShomer/Hockey-Scraper) - This was the main source of reference for this scraper. Some parts of this library were directly translated from Python into Julia. Many thanks to Harry for a fantastic library!
