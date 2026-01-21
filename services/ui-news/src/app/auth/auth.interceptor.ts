import { HttpInterceptorFn, HttpErrorResponse } from '@angular/common/http';
import { inject } from '@angular/core';
import { tokenKey } from './storage';
import { AuthTokenService } from './token.service';
import { RefreshService } from './refresh.service';
import { catchError, switchMap, throwError, from } from 'rxjs';

// Simple allowlist: only attach Authorization to our API gateway paths.
const ALLOWLIST = [
  /^\/api\//,                    // dev server relative path
  /^https:\/\/localhost\/api\// // absolute through UI gateway
];

const REALM = 'news';
const CLIENT_ID = 'news-web';

export const authInterceptor: HttpInterceptorFn = (req, next) => {
  try {
    const url = req.url || '';
    const shouldAttach = ALLOWLIST.some((re) => re.test(url));
    console.debug('[auth-interceptor]', { url, shouldAttach });
    if (!shouldAttach) {
      const tokenSvcSkip = inject(AuthTokenService);
      try { tokenSvcSkip.markSkipped(url); } catch (_) {}
      return next(req);
    }
    const tokenSvc = inject(AuthTokenService);
    let token = tokenSvc.getToken();
    if (!token) {
      const key = tokenKey(REALM, CLIENT_ID);
      token = sessionStorage.getItem(key);
    }
    if (!token) {
      try { tokenSvc.markSkipped(url); } catch (_) {}
      return next(req);
    }
    const authReq = req.clone({
      setHeaders: {
        Authorization: `Bearer ${token}`
      }
    });
    try { tokenSvc.markAttached(url, token); } catch (_) {}
    debugger; // Dev: pause here to verify interceptor path
    const refresher = inject(RefreshService);
    return next(authReq).pipe(
      catchError((err) => {
        if (err instanceof HttpErrorResponse && err.status === 401) {
          return from(refresher.refresh()).pipe(
            switchMap((newToken) => {
              if (newToken) {
                const retryReq = req.clone({
                  setHeaders: { Authorization: `Bearer ${newToken}` }
                });
                return next(retryReq);
              }
              return throwError(() => err);
            })
          );
        }
        return throwError(() => err);
      })
    );
  } catch (_) {
    return next(req);
  }
};
