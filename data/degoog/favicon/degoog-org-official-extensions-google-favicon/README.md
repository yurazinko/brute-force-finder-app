# Google Favicons

Gets a 64px icon from Google's favicon service:

```
https://www.google.com/s2/favicons?domain=<host>&sz=64
```

This is what degoog used before favicons became extensions.

## Privacy

Google sees every domain in your results. The requests come from your server's IP, or from the proxy or transport you set for this provider. Your visitors and their queries never reach Google, but a burst of domains arriving together still hints at what someone searched.

If Google has no icon for a domain, degoog tries the next provider.
