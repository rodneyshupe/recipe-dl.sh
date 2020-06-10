# recipe-dl

Recipe download script.  Will format the recipe into JSON, Markdown,
or reStructuredText.  I tend to use more reStructuredText so that is the
default output format.

## Usage

```
Usage: ./recipe-dl.sh [-ahjmros] [-i infile] [-o outfile] <URL> [<URL] ...
  -a|--authorize         Force authorization of Cook Illustrated sites
  -h|--help              Display help
  -j|--output-json       Output results in JSON format
  -m|--output-md         Output results in Markdown format
  -r|--output-rst        Output results in reStructuredText format
  -i|--inputfile infile  (Currently Unsupported) Specify input JSON file infile
  -o|--outfile outfile   Specify output file outfile
  -s|--save-to-file      Save output file(s)
```

## Compatibility

Currently this has been tested for the following sites:
* [Cook's Illustrated](www.cooksillustrated.com) (Subscription Required)
* [Cook's Country](www.cookscountry.com) (Subscription Required)
* [America's Test Kitchen](www.americatestkitchen.com) (Subscription Required)
* [New York Times](cooking.nytimes.com)
* [Bon Appetit](www.bonappetit.com)
* [FoodNetwork.com](www.foodnetwork.com)
* [CookingChannelTV.com](www.cookingchanneltv.com)

## Install
Copy recipe-dl.sh to somewhere on your path.
```sh
curl https://raw.githubusercontent.com/rodneyshupe/recipe-dl/master/recipe-dl.sh --output recipe-dl.sh && chmod + x recipe-dl.sh
```

### Requirements
The following packages are required:
* [curl](https://curl.haxx.se/)
* [jq](https://stedolan.github.io/jq/)
* [html-xml-utils](https://www.w3.org/Tools/HTML-XML-utils/)
