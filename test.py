import httpx
import asyncio

async def main():
    try:
        client = httpx.AsyncClient(base_url='https://vtop.vitap.ac.in', headers={'User-Agent': 'Mozilla/5.0'}, verify=False)
        resp = await client.get('/vtop/open/page')
        print(resp.status_code)
        print(resp.text[:100])
        await client.aclose()
    except Exception as e:
        print(repr(e))

asyncio.run(main())
