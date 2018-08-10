// ref https://github.com/Azure/azure-sdk-for-node/issues/2416
import * as fs from 'fs'
import * as MsRest from 'ms-rest-azure'
const config = require('../lib/settings')

class MyTokenCache {
    private tokens: any[] = []
    constructor(readonly clusterId: string) {
        this.load()
    }

    isSecureCache() {
        throw 'isSecureCache not implemented'
    }

    add(entries: any, cb: any) {
        this.tokens.push(...entries)
        cb()
    }

    remove(entries: any, cb: any) {
        this.tokens = this.tokens.filter((e) => {
            return !(Object.keys(entries[0]).every( key => e[key] === entries[0][key] ))
        })
        cb()
    }

    clear(cb: any) {
        this.tokens = []
        cb()
    }

    find(query, cb) {
        let result = this.tokens.filter((e) => {
            return Object.keys(query).every( key => e[key] === query[key] )
        })
        cb(null, result)
    }

    //
    // Methods specific to MyTokenCache
    //
    empty() {
        this.deleteOld()
        return this.tokens.length === 0
    }

    first() {
        return this.tokens[0]
    }

    private filename() {
        return config.credentialStore[config.profile || 'default']
    }
    private load() {
        try {
            this.tokens = JSON.parse(fs.readFileSync(this.filename()).toString())
            this.tokens.map(t => t.expiresOn = new Date(t.expiresOn))
        }
        catch (e) {}
    }

    save() {
        
        fs.writeFileSync(this.filename(), JSON.stringify(this.tokens)) }

    private deleteOld() {
        this.tokens = this.tokens.filter( t => t.expiresOn > Date.now() - 5*60*1000)
    }

}

let tokenCache:MyTokenCache

export async function getCredentials(clusterId: string): Promise<MsRest.DeviceTokenCredentials> {
    if(!tokenCache) {
        tokenCache = new MyTokenCache(clusterId)
    }

    if( clusterId !== tokenCache.clusterId ) {
        throw `clusterId ${clusterId} !== ${tokenCache.clusterId}`
    }

    if(tokenCache.empty()) {
        let credentials = await MsRest.interactiveLogin({tokenCache})
        tokenCache.save()
        return credentials
    }
    else {
        let options: MsRest.DeviceTokenCredentialsOptions = {}
        let token = tokenCache.first()
        options.tokenCache = tokenCache
        options.username = token.userId

        let credentials = new MsRest.DeviceTokenCredentials(options)
        return credentials
    }
}
