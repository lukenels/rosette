#lang racket

(require rackunit/text-ui rackunit rosette/lib/roseunit "solver.rkt")
(require rosette/base/core/exn rosette/base/core/result)
(require rosette/base/adt/box)
(require (only-in rosette/base/form/define define-symbolic)
         (only-in rosette/base/core/bool
                  @boolean? @true? && ! => <=>
                  vc clear-vc! with-vc merge-vc!
                  $assume $assert @assume @assert
                  spec-tt spec-tt?
                  spec-assumes spec-asserts)
         (only-in rosette/base/core/real @integer? @=)
         (only-in rosette/base/core/merge merge merge*))

(provide check-vc-eqv check-exn-svm)

(define (check-vc-eqv assumes asserts)
  (define actual (vc))
  (check-unsat (solve (! (&&  (<=> (spec-assumes actual) assumes) (<=> (spec-asserts actual) asserts))))))

(define-syntax (check-exn-svm stx)
  (syntax-case stx ()
    [(_ kind? thunk) #'(check-exn-svm kind? #rx".*" thunk)]
    [(_ kind? rx thunk)
     #'(check-exn
        (lambda (ex)
          (and (kind? ex)
               (regexp-match rx (exn-message ex))))
        thunk)]))

(define-syntax-rule (check-assume-or-assert $a @a user? core? spec-a spec-other)
  (begin
    ;---------------------------;
    (define (check-vc expected-a expected-other)
      (define actual (vc))
      (check-equal? (spec-a actual) expected-a)
      (check-equal? (spec-other actual) expected-other))
    ;---------------------------;
    ($a #t)
    (check-pred spec-tt? (vc))
    ($a 1)
    (check-pred spec-tt? (vc))
    ;---------------------------;
    (check-exn-svm user? #rx"failed" (thunk (@a #f)))
    (check-vc #f #t)
    (clear-vc!)
    ;---------------------------;
    (check-pred spec-tt? (vc))
    (check-exn-svm user? #rx"test" (thunk (@a #f "test")))
    (check-vc #f #t)
    (clear-vc!)
    ;---------------------------;
    (check-exn-svm core? #rx"failed" (thunk ($a #f)))
    (check-vc #f #t)
    (clear-vc!)
    ;---------------------------;
    (check-exn-svm core? #rx"test" (thunk ($a #f "test")))
    (check-vc #f #t)
    (clear-vc!)
    ;---------------------------;
    (define-symbolic b c @boolean?)
    (@a b)
    (check-vc b #t)
    (check-exn-svm user? #rx"contradiction" (thunk (@a (! b))))
    (check-vc  #f #t)
    (clear-vc!)
    ;---------------------------;
    ($a b)
    (check-exn-svm core? #rx"contradiction" (thunk ($a (! b))))
    (check-vc #f #t)
    (clear-vc!)
    ;---------------------------;
    ($a (merge b #f 1))
    (check-vc (@true? (merge b #f 1)) #t)
    (clear-vc!)
    ;---------------------------;
    ($a b)
    ($a c)
    (check-vc (&& b c) #t)
    (clear-vc!)))

(define (check-assumes)
   (check-assume-or-assert $assume @assume exn:fail:svm:assume:user? exn:fail:svm:assume:core?
                           spec-assumes spec-asserts))

(define (check-asserts)
   (check-assume-or-assert $assert @assert exn:fail:svm:assert:user? exn:fail:svm:assert:core?
                           spec-asserts spec-assumes))

(define (spec->pair s) (cons (spec-assumes s) (spec-asserts s)))


(define (check-with-vc-0)
  (define-symbolic a @boolean?)
  ;---------------------------;
  (check-match (with-vc (@assume 1)) (ans (? void?) (? spec-tt?)))
  (check-pred spec-tt? (vc))
  (check-match (with-vc (@assume a)) (ans (? void?) (app spec->pair (cons (== a) #t))))
  (check-pred spec-tt? (vc))
  (check-match (with-vc (@assume #f)) (halt (? exn:fail:svm:assume:user?) (app spec->pair (cons #f #t))))
  (check-match (with-vc ($assume #f)) (halt (? exn:fail:svm:assume:core?) (app spec->pair (cons #f #t))))
  ;---------------------------;
  (check-match (with-vc (@assert 1)) (ans (? void?) (? spec-tt?)))
  (check-pred spec-tt? (vc))
  (check-match (with-vc (@assert a)) (ans (? void?) (app spec->pair (cons #t (== a)))))
  (check-pred spec-tt? (vc))
  (check-match (with-vc (@assert #f)) (halt (? exn:fail:svm:assert:user?) (app spec->pair (cons #t #f))))
  (check-match (with-vc ($assert #f)) (halt (? exn:fail:svm:assert:core?) (app spec->pair (cons #t #f))))
  (check-match (with-vc (1)) (halt (? exn:fail:svm:assert:err?) (app spec->pair (cons #t #f)))))

(define (check-with-vc-1)
  (define-symbolic a b c d @boolean?)
  ;---------------------------;
  (check-match (with-vc (begin (@assume a) (@assume b))) (ans (? void?) (app spec->pair (cons (== (&& a b)) #t))))
  (check-match (with-vc (begin (@assert a) (@assert b))) (ans (? void?) (app spec->pair (cons #t (== (&& a b))))))
  (check-match (with-vc (begin (@assume a) (@assert b))) (ans (? void?) (app spec->pair (cons (== a) (== (=> a b))))))
  (check-match (with-vc (begin (@assert a) (@assume b))) (ans (? void?) (app spec->pair (cons (== (=> a b)) (== a)))))
  ;---------------------------;
  (check-match (with-vc (begin (@assume a) (@assume (! a)))) (halt (? exn:fail:svm:assume:user?) (app spec->pair (cons #f #t))))
  (check-match (with-vc (begin ($assume a) (@assume (! a)))) (halt (? exn:fail:svm:assume:user?) (app spec->pair (cons #f #t))))
  (check-match (with-vc (begin (@assume (! a)) ($assume a))) (halt (? exn:fail:svm:assume:core?) (app spec->pair (cons #f #t))))
  (check-match (with-vc (begin ($assume (! a)) ($assume a))) (halt (? exn:fail:svm:assume:core?) (app spec->pair (cons #f #t))))
  ;---------------------------;
  (check-match (with-vc (begin (@assert a) (@assert (! a)))) (halt (? exn:fail:svm:assert:user?) (app spec->pair (cons #t #f))))
  (check-match (with-vc (begin ($assert a) (@assert (! a)))) (halt (? exn:fail:svm:assert:user?) (app spec->pair (cons #t #f))))
  (check-match (with-vc (begin (@assert (! a)) ($assert a))) (halt (? exn:fail:svm:assert:core?) (app spec->pair (cons #t #f))))
  (check-match (with-vc (begin ($assert (! a)) ($assert a))) (halt (? exn:fail:svm:assert:core?) (app spec->pair (cons #t #f))))
  (check-match (with-vc (begin (@assert a) (1))) (halt (? exn:fail:svm:assert:err?) (app spec->pair (cons #t #f))))
  ;---------------------------;
  (check-match (with-vc (begin (@assume a) (@assert #f))) (halt (? exn:fail:svm:assert:user?) (app spec->pair (cons (== a) (== (! a))))))
  (check-match (with-vc (begin (@assume a) ($assert #f))) (halt (? exn:fail:svm:assert:core?) (app spec->pair (cons (== a) (== (! a))))))
  (check-match (with-vc (begin (@assume a) (1))) (halt (? exn:fail:svm:assert:err?) (app spec->pair (cons (== a) (== (! a))))))
  ;---------------------------;
  (check-match (with-vc (begin (@assert a) (@assume #f))) (halt (? exn:fail:svm:assume:user?) (app spec->pair (cons (== (! a)) (== a)))))
  (check-match (with-vc (begin (@assert a) ($assume #f))) (halt (? exn:fail:svm:assume:core?) (app spec->pair (cons (== (! a)) (== a)))))
  ;---------------------------;
  (check-match (with-vc (begin (@assume #f) (@assert a))) (halt (? exn:fail:svm:assume:user?) (app spec->pair (cons #f #t))))
  (check-match (with-vc (begin (@assert #f) (@assume a))) (halt (? exn:fail:svm:assert:user?) (app spec->pair (cons #t #f))))
  (check-match (with-vc (begin (1) (@assume a))) (halt (? exn:fail:svm:assert:err?) (app spec->pair (cons #t #f))))
  ;---------------------------;
  (check-match (with-vc (begin (@assume a) (1) (@assert b))) (halt (? exn:fail:svm:assert:err?) (app spec->pair (cons (== a) (== (! a))))))
  ;---------------------------;
  (check-match (with-vc (begin (@assume a) (@assume b) (@assert c) (@assert d)))
               (ans (? void?) (app spec->pair (cons (== (&& a b)) (== (&& (=> (&& a b) c) (=> (&& a b) d)))))))
  (check-match (with-vc (begin (@assert a) (@assert b) (@assume c) (@assume d)))
               (ans (? void?) (app spec->pair (cons (== (&& (=> (&& a b) c) (=> (&& a b) d))) (== (&& a b))))))
  (check-match (with-vc (begin (@assume a) (@assert b) (@assume c) (@assert d)))
               (ans (? void?) (app spec->pair (cons (== (&& a (=> (=> a b) c))) (== (&& (=> a b) (=> (&& a (=> (=> a b) c)) d)))))))
  (check-match (with-vc (begin (@assert a) (@assume b) (@assert c) (@assume d)))
               (ans (? void?) (app spec->pair (cons (== (&& (=> a b) (=> (&& a (=> (=> a b) c)) d))) (== (&& a (=> (=> a b) c)))))))
  ;---------------------------;
  (check-match (with-vc (begin (@assume a) (@assert b) (@assume #f) (@assert d)))
               (halt (? exn:fail:svm:assume:user?) (app spec->pair (cons (== (&& a (=> (=> a b) #f))) (== (=> a b))))))
  (check-match (with-vc (begin (@assume a) (@assert b) (1) (@assert d)))
               (halt (? exn:fail:svm:assert:err?) (app spec->pair (cons (== a) (== (&& (=> a b) (=> a #f)))))))
  ;---------------------------;
  (@assume a)
  (@assert b)
  (check-match (vc) (app spec->pair (cons (== a) (== (=> a b)))))
  (check-match (with-vc (begin  (@assume c) (@assert d)))
               (ans (? void?) (app spec->pair (cons (== (&& a (=> (=> a b) c))) (== (&& (=> a b) (=> (&& a (=> (=> a b) c)) d)))))))
  (check-match (vc) (app spec->pair (cons (== a) (== (=> a b)))))
  (clear-vc!))
  
  
(define (check-merge-vc-0)
  (define-symbolic a b c @boolean?)
  ;---------------------------;
  (merge-vc! null null)
  (check-pred spec-tt? (vc))
  ;---------------------------;
  (match-define (ans _ vc0) (with-vc (begin (@assume a) (@assert b))))
  (merge-vc! (list #t) (list vc0))
  (check-match (vc) (app spec->pair (cons (== a) (== (=> a b)))))
  (clear-vc!)
  (merge-vc! (list c) (list vc0))
  (check-match (vc) (app spec->pair (cons (== (=> c a)) (== (=> c (=> a b))))))
  (clear-vc!)
  (merge-vc! (list #f) (list vc0))
  (check-pred spec-tt? (vc))
  ;---------------------------;
  (match-define (halt _ vc1) (with-vc (@assume #f)))
  (merge-vc! (list #f) (list vc1))
  (check-pred spec-tt? (vc))
  (merge-vc! (list c) (list vc1))
  (check-match (vc) (app spec->pair (cons (== (=> c #f)) #t)))
  (check-exn-svm exn:fail:svm:assume:core? #rx"contradiction" (thunk (merge-vc! (list #t) (list vc1))))
  (clear-vc!)
  ;---------------------------;
  (match-define (halt _ vc2) (with-vc (@assert #f)))
  (merge-vc! (list #f) (list vc2))
  (check-pred spec-tt? (vc))
  (merge-vc! (list c) (list vc2))
  (check-match (vc) (app spec->pair (cons #t (==  (=> c #f)))))
  (check-exn-svm exn:fail:svm:assert:core? #rx"contradiction" (thunk (merge-vc! (list #t) (list vc2))))
  (clear-vc!)
  ;---------------------------;
  (@assume a)
  (match-define (ans _ vc3) (with-vc spec-tt (@assume (! a))))
  (check-exn-svm exn:fail:svm:assume:core? #rx"contradiction" (thunk (merge-vc! (list #t) (list vc3))))
  (check-match (vc) (app spec->pair (cons #f #t)))
  (clear-vc!)
  ;---------------------------;
  (@assert a)
  (match-define (ans _ vc4) (with-vc spec-tt (@assert (! a))))
  (check-exn-svm exn:fail:svm:assert:core? #rx"contradiction" (thunk (merge-vc! (list #t) (list vc4))))
  (check-match (vc) (app spec->pair (cons #t #f)))
  (clear-vc!))

(define (check-merge-vc-1)
  (define-symbolic a b c d e @boolean?)
  (define not-a (! a))
  (merge-vc! (list a not-a) (list spec-tt spec-tt))
  (check-pred spec-tt? (vc))
  ;---------------------------;
  (merge-vc! (list a not-a) (list (result-state (with-vc (@assume b))) (result-state (with-vc (@assume c)))))
  (check-match (vc) (app spec->pair (cons (== (&& (=> a b) (=> not-a c))) #t)))
  (clear-vc!)
  (merge-vc! (list a not-a) (list (result-state (with-vc (@assert b))) (result-state (with-vc (@assert c)))))
  (check-match (vc) (app spec->pair (cons #t (== (&& (=> a b) (=> not-a c))))))
  (clear-vc!)
  (merge-vc! (list a not-a) (list (result-state (with-vc (@assume b))) (result-state (with-vc (@assert c)))))
  (check-match (vc) (app spec->pair (cons (== (=> a b)) (== (=> not-a c)))))
  (clear-vc!)
  (merge-vc! (list a not-a) (list (result-state (with-vc (@assert b))) (result-state (with-vc (@assume c)))))
  (check-match (vc) (app spec->pair (cons (== (=> not-a c)) (== (=> a b)))))
  (clear-vc!)
  (@assume d)
  (@assert e)
  (merge-vc! (list a not-a) (list (result-state (with-vc (@assume b))) (result-state (with-vc (@assert c)))))
  (check-vc-eqv (&& d (=> a (=> e b))) (&& (=> d e) (=> not-a (=> d c))))
  (clear-vc!)
  ;---------------------------;
  (merge-vc! (list a not-a) (list (result-state (with-vc (@assume #f))) (result-state (with-vc (@assert c)))))
  (check-vc-eqv (! a) (=> not-a c))
  (clear-vc!)
  (merge-vc! (list a not-a) (list (result-state (with-vc (@assume b))) (result-state (with-vc (@assert #f)))))
  (check-vc-eqv (=> a b) (! not-a))
  (clear-vc!)
  (check-exn-svm exn:fail:svm:assume:core? #rx"contradiction"
                 (thunk (merge-vc! (list a not-a)
                                   (list (result-state (with-vc (@assume #f)))
                                         (result-state (with-vc (@assume #f)))))))
  (check-match (vc) (app spec->pair (cons #f #t)))
  (clear-vc!)
  (check-exn-svm exn:fail:svm:assert:core? #rx"contradiction"
                 (thunk (merge-vc! (list a not-a)
                                   (list (result-state (with-vc (@assert #f)))
                                         (result-state (with-vc (@assert #f)))))))
  (check-match (vc) (app spec->pair (cons #t #f)))
  (clear-vc!)
  (merge-vc! (list a not-a) (list (result-state (with-vc (@assume #f))) (result-state (with-vc (@assert #f)))))
  (check-match (vc) (app spec->pair (cons (== not-a) (== a))))
  (merge-vc! (list a not-a) (list (result-state (with-vc (@assert #f))) (result-state (with-vc (@assume #f)))))
  (check-match (vc) (app spec->pair (cons (== not-a) (== a))))
  (clear-vc!))

(define assume-tests
  (test-suite+
   "Basic assume tests for rosette/base/core/vc.rkt"
   (check-assumes)))

(define assert-tests
  (test-suite+
   "Basic assert tests for rosette/base/core/vc.rkt"
   (check-asserts)))

(define with-vc-tests
  (test-suite+
   "Tests for with-vc in rosette/base/core/vc.rkt"
   (check-with-vc-0)
   (check-with-vc-1)))

(define merge-vc-tests
  (test-suite+
   "Tests for merge-vc! in rosette/base/core/vc.rkt"
   (check-merge-vc-0)
   (check-merge-vc-1)))

(module+ test
  (time (run-tests assume-tests))
  (time (run-tests assert-tests))
  (time (run-tests with-vc-tests))
  (time (run-tests merge-vc-tests)))