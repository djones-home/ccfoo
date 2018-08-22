"use strict";
var __awaiter = (this && this.__awaiter) || function (thisArg, _arguments, P, generator) {
    return new (P || (P = Promise))(function (resolve, reject) {
        function fulfilled(value) { try { step(generator.next(value)); } catch (e) { reject(e); } }
        function rejected(value) { try { step(generator["throw"](value)); } catch (e) { reject(e); } }
        function step(result) { result.done ? resolve(result.value) : new P(function (resolve) { resolve(result.value); }).then(fulfilled, rejected); }
        step((generator = generator.apply(thisArg, _arguments || [])).next());
    });
};
var __generator = (this && this.__generator) || function (thisArg, body) {
    var _ = { label: 0, sent: function() { if (t[0] & 1) throw t[1]; return t[1]; }, trys: [], ops: [] }, f, y, t, g;
    return g = { next: verb(0), "throw": verb(1), "return": verb(2) }, typeof Symbol === "function" && (g[Symbol.iterator] = function() { return this; }), g;
    function verb(n) { return function (v) { return step([n, v]); }; }
    function step(op) {
        if (f) throw new TypeError("Generator is already executing.");
        while (_) try {
            if (f = 1, y && (t = op[0] & 2 ? y["return"] : op[0] ? y["throw"] || ((t = y["return"]) && t.call(y), 0) : y.next) && !(t = t.call(y, op[1])).done) return t;
            if (y = 0, t) op = [op[0] & 2, t.value];
            switch (op[0]) {
                case 0: case 1: t = op; break;
                case 4: _.label++; return { value: op[1], done: false };
                case 5: _.label++; y = op[1]; op = [0]; continue;
                case 7: op = _.ops.pop(); _.trys.pop(); continue;
                default:
                    if (!(t = _.trys, t = t.length > 0 && t[t.length - 1]) && (op[0] === 6 || op[0] === 2)) { _ = 0; continue; }
                    if (op[0] === 3 && (!t || (op[1] > t[0] && op[1] < t[3]))) { _.label = op[1]; break; }
                    if (op[0] === 6 && _.label < t[1]) { _.label = t[1]; t = op; break; }
                    if (t && _.label < t[2]) { _.label = t[2]; _.ops.push(op); break; }
                    if (t[2]) _.ops.pop();
                    _.trys.pop(); continue;
            }
            op = body.call(thisArg, _);
        } catch (e) { op = [6, e]; y = 0; } finally { f = t = 0; }
        if (op[0] & 5) throw op[1]; return { value: op[0] ? op[1] : void 0, done: true };
    }
};
exports.__esModule = true;
// ref https://github.com/Azure/azure-sdk-for-node/issues/2416
var fs = require("fs");
var MsRest = require("ms-rest-azure");
var config = require('../lib/settings').load()
var MyTokenCache = /** @class */ (function () {
    function MyTokenCache(clusterId) {
        this.clusterId = clusterId;
        this.tokens = [];
        this.load();
    }
    MyTokenCache.prototype.isSecureCache = function () {
        throw 'isSecureCache not implemented';
    };
    MyTokenCache.prototype.add = function (entries, cb) {
        var _a;
        (_a = this.tokens).push.apply(_a, entries);
        cb();
    };
    MyTokenCache.prototype.remove = function (entries, cb) {
        this.tokens = this.tokens.filter(function (e) {
            return !(Object.keys(entries[0]).every(function (key) { return e[key] === entries[0][key]; }));
        });
        cb();
    };
    MyTokenCache.prototype.clear = function (cb) {
        this.tokens = [];
        cb();
    };
    MyTokenCache.prototype.find = function (query, cb) {
        var result = this.tokens.filter(function (e) {
            return Object.keys(query).every(function (key) { return e[key] === query[key]; });
        });
        cb(null, result);
    };
    //
    // Methods specific to MyTokenCache
    //
    MyTokenCache.prototype.empty = function () {
        this.deleteOld();
        return this.tokens.length === 0;
    };
    MyTokenCache.prototype.first = function () {
        return this.tokens[0];
    };
    MyTokenCache.prototype.filename = function () {
        return config.credentialStore[config.profile || 'default'];
    };
    MyTokenCache.prototype.load = function () {
        try {
            this.tokens = JSON.parse(fs.readFileSync(this.filename()).toString());
            this.tokens.map(function (t) { return t.expiresOn = new Date(t.expiresOn); });
        }
        catch (e) { }
    };
    MyTokenCache.prototype.save = function () {
        fs.writeFileSync(this.filename(), JSON.stringify(this.tokens));
    };
    MyTokenCache.prototype.deleteOld = function () {
        this.tokens = this.tokens.filter(function (t) { return t.expiresOn > Date.now() - 5 * 60 * 1000; });
    };
    return MyTokenCache;
}());
var tokenCache;
function getCredentials(clusterId) {
    return __awaiter(this, void 0, void 0, function () {
        var credentials, options, token, credentials;
        return __generator(this, function (_a) {
            switch (_a.label) {
                case 0:
                    if (!tokenCache) {
                        tokenCache = new MyTokenCache(clusterId);
                    }
                    if (clusterId !== tokenCache.clusterId) {
                        throw "clusterId " + clusterId + " !== " + tokenCache.clusterId;
                    }
                    if (!tokenCache.empty()) return [3 /*break*/, 2];
                    return [4 /*yield*/, MsRest.interactiveLogin({ tokenCache: tokenCache })];
                case 1:
                    credentials = _a.sent();
                    tokenCache.save();
                    return [2 /*return*/, credentials];
                case 2:
                    options = {};
                    token = tokenCache.first();
                    options.tokenCache = tokenCache;
                    options.username = token.userId;
                    credentials = new MsRest.DeviceTokenCredentials(options);
                    return [2 /*return*/, credentials];
            }
        });
    });
}
exports.getCredentials = getCredentials;
