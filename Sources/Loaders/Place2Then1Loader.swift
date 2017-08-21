import Gnomon
import RxSwift

public protocol P2T1Loader: class {
  associatedtype P2T1LFirstResult1: OptionalResult
  associatedtype P2T1LFirstResult2: OptionalResult
  associatedtype P2T1LSecondResult: OptionalResult

  typealias P2T1LFirstRequests = (Request<P2T1LFirstResult1>, Request<P2T1LFirstResult2>)
  typealias P2T1LFirstResults = (P2T1LFirstResult1, P2T1LFirstResult2)
  typealias P2T1LSecondRequest = Request<P2T1LSecondResult>
  typealias P2T1LResults = (P2T1LFirstResult1, P2T1LFirstResult2, P2T1LSecondResult)

  func requests(for loadingIntent: LoaderIntent) throws -> P2T1LFirstRequests
  func request(for loadingIntent: LoaderIntent, from firstResults: P2T1LFirstResults) throws -> P2T1LSecondRequest

  func sections(from results: P2T1LResults, loadingIntent: LoaderIntent) -> [Sectionable]?
  func didReceive(results: P2T1LResults, loadingIntent: LoaderIntent)
}

public extension P2T1Loader {
  func didReceive(results: P2T1LResults, loadingIntent: LoaderIntent) {}
}

public func astrLoad<T: P2T1Loader>(p2t1Loader loader: T, intent: LoaderIntent) -> SectionObservable {
  do {
    let (request1, request2) = try loader.requests(for: intent)

    let cachedZip = Observable.zip(Gnomon.cachedModels(for: request1), Gnomon.cachedModels(for: request2))
    let cached = cachedZip.flatMap { [weak loader] res1, res2 -> SectionObservable in
      guard let request = try loader?.request(for: intent, from: (res1.result, res2.result)) else { return .just(nil) }
      let observable = Gnomon.cachedModels(for: request)
      return observable.flatMap { [weak loader] res -> SectionObservable in
        let results = (res1.result, res2.result, res.result)
        return Observable.just(loader?.sections(from: results, loadingIntent: intent)).do(onNext: { _ in
          loader?.didReceive(results: results, loadingIntent: intent)
        }).subscribeOn(MainScheduler.instance)
      }
    }

    let httpZip = Observable.zip(Gnomon.models(for: request1), Gnomon.models(for: request2))
    let http = httpZip.flatMap { [weak loader] res1, res2 -> SectionObservable in
      guard let request = try loader?.request(for: intent, from: (res1.result, res2.result)) else { return .just(nil) }
      let observable = Gnomon.models(for: request)
      return observable.flatMap { [weak loader] res -> SectionObservable in
        if res.responseType == .httpCache {
          return .empty()
        } else {
          let results = (res1.result, res2.result, res.result)
          return Observable.just(loader?.sections(from: results, loadingIntent: intent)).do(onNext: { _ in
            loader?.didReceive(results: results, loadingIntent: intent)
          }).subscribeOn(MainScheduler.instance)
        }
      }
    }

    return cached.concat(http).subscribeOn(ConcurrentDispatchQueueScheduler(qos: .default))
      .observeOn(MainScheduler.instance)
  } catch {
    return .error(error)
  }
}
