# DuckDuckGo Favicons

Gets icons from DuckDuckGo's favicon service. It mostly returns each site's own `.ico`, so a site that only ships a 16px icon stays at 16px:

```
https://icons.duckduckgo.com/ip3/<host>.ico
```

## Privacy

DuckDuckGo sees every domain in your results. The requests come from your server's IP, or from the proxy or transport you set for this provider. Your visitors and their queries never reach DuckDuckGo, but a burst of domains arriving together still hints at what someone searched.

If DuckDuckGo has no icon for a domain, degoog tries the next provider.
