;;; erc-scenarios-local-modules.el --- Local modules tests for ERC -*- lexical-binding: t -*-

;; Copyright (C) 2022 Free Software Foundation, Inc.
;;
;; This file is part of GNU Emacs.
;;
;; This program is free software: you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see
;; <https://www.gnu.org/licenses/>.

;;; Code:

;;; Commentary:

;; These tests all use `sasl' because, as of ERC 5.5, it's the one
;; and only local module.

(require 'ert-x)
(eval-and-compile
  (let ((load-path (cons (ert-resource-directory) load-path)))
    (require 'erc-scenarios-common)))

(require 'erc-sasl)

;; This asserts that a local module's options and its inclusion in
;; (and absence from) `erc-update-modules' can be let-bound.

(ert-deftest erc-scenarios-base-local-modules--reconnect-let ()
  :tags '(:expensive-test)
  (erc-scenarios-common-with-cleanup
      ((erc-scenarios-common-dialog "sasl")
       (erc-server-flood-penalty 0.1)
       (dumb-server (erc-d-run "localhost" t 'plain 'plain))
       (port (process-contact dumb-server :service))
       (expect (erc-d-t-make-expecter)))

    (ert-info ("Connect with options let-bound")
      (with-current-buffer
          ;; This won't work unless the library is already loaded
          (let ((erc-modules (cons 'sasl erc-modules))
                (erc-sasl-mechanism 'plain)
                (erc-sasl-password "password123"))
            (erc :server "127.0.0.1"
                 :port port
                 :nick "tester"
                 :user "tester"
                 :full-name "tester"))
        (should (string= (buffer-name) (format "127.0.0.1:%d" port)))))

    (with-current-buffer (erc-d-t-wait-for 10 (get-buffer "ExampleOrg"))

      (ert-info ("First connection succeeds")
        (funcall expect 10 "This server is in debug mode")
        (erc-cmd-QUIT "")
        (funcall expect 10 "finished"))

      (should-not (memq 'sasl erc-modules))
      (erc-d-t-wait-for 10 (not (erc-server-process-alive)))
      (erc-cmd-RECONNECT)

      (ert-info ("Second connection succeeds")
        (funcall expect 10 "This server is in debug mode")
        (erc-cmd-QUIT "")
        (funcall expect 10 "finished")))))

;; After quitting a session for which `sasl' is enabled, you
;; disconnect and toggle `erc-sasl-mode' off.  You then reconnect
;; using an alternate nickname.  You again disconnect and reconnect,
;; this time immediately, and the mode stays disabled.  Finally, you
;; once again disconnect, toggle the mode back on, and reconnect.  You
;; are authenticated successfully, just like in the initial session.
;;
;; This is meant to show that a user's local mode settings persist
;; between sessions.  It also happens to show (in round four, below)
;; that a server renicking a user on 001 after a 903 is handled just
;; like a user-initiated renick, although this is not the main thrust.

(ert-deftest erc-scenarios-base-local-modules--mode-persistence ()
  :tags '(:expensive-test)
  (erc-scenarios-common-with-cleanup
      ((erc-scenarios-common-dialog "base/local-modules")
       (erc-server-flood-penalty 0.1)
       (dumb-server (erc-d-run "localhost" t 'first 'second 'third 'fourth))
       (port (process-contact dumb-server :service))
       (erc-modules (cons 'sasl erc-modules))
       (expect (erc-d-t-make-expecter))
       (server-buffer-name (format "127.0.0.1:%d" port)))

    (ert-info ("Round one, initial authentication succeeds as expected")
      (with-current-buffer (erc :server "127.0.0.1"
                                :port port
                                :nick "tester"
                                :user "tester"
                                :password "changeme"
                                :full-name "tester")
        (should (string= (buffer-name) server-buffer-name))
        (funcall expect 10 "You are now logged in as tester"))

      (with-current-buffer (erc-d-t-wait-for 10 (get-buffer "foonet"))
        (funcall expect 10 "This server is in debug mode")
        (erc-cmd-JOIN "#chan")

        (with-current-buffer (erc-d-t-wait-for 10 (get-buffer "#chan"))
          (funcall expect 20 "She is Lavinia, therefore must"))

        (erc-cmd-QUIT "")
        (funcall expect 10 "finished")))

    (ert-info ("Round two, nick rejected, alternate granted")
      (with-current-buffer "foonet"

        (ert-info ("Toggle mode off, reconnect")
          (erc-sasl-mode -1)
          (erc-cmd-RECONNECT))

        (funcall expect 10 "User modes for tester`")
        (should-not (cdr (erc-scenarios-common-buflist "foonet")))
        (should (equal (buffer-name) "foonet"))
        (should-not (cdr (erc-scenarios-common-buflist "#chan")))

        (with-current-buffer "#chan"
          (funcall expect 10 "Some enigma, some riddle"))

        (erc-cmd-QUIT "")
        (funcall expect 10 "finished")))

    (ert-info ("Round three, send alternate nick initially")
      (with-current-buffer "foonet"

        (ert-info ("Keep mode off, reconnect")
          (should-not erc-sasl-mode)
          (should (local-variable-p 'erc-sasl-mode))
          (erc-cmd-RECONNECT))

        (funcall expect 10 "User modes for tester`")
        (should-not (cdr (erc-scenarios-common-buflist "foonet")))
        (should (equal (buffer-name) "foonet"))
        (should-not (cdr (erc-scenarios-common-buflist "#chan")))

        (with-current-buffer "#chan"
          (funcall expect 10 "Let our reciprocal vows be remembered."))

        (erc-cmd-QUIT "")
        (funcall expect 10 "finished")))

    (ert-info ("Round four, authenticated successfully again")
      (with-current-buffer "foonet"

        (ert-info ("Toggle mode on, reconnect")
          (should-not erc-sasl-mode)
          (should (local-variable-p 'erc-sasl-mode))
          (erc-sasl-mode +1)
          (erc-cmd-RECONNECT))

        (funcall expect 10 "User modes for tester")
        (should-not (cdr (erc-scenarios-common-buflist "foonet")))
        (should (equal (buffer-name) "foonet"))
        (should-not (cdr (erc-scenarios-common-buflist "#chan")))

        (with-current-buffer "#chan"
          (funcall expect 10 "Well met; good morrow, Titus and Hortensius."))

        (erc-cmd-QUIT "")))))

;; For local modules, the twin toggle commands `erc-FOO-enable' and
;; `erc-FOO-disable' affect all buffers of a connection, whereas
;; `erc-FOO-mode' continues to operate only on the current buffer.

(ert-deftest erc-scenarios-base-local-modules--toggle-helpers ()
  :tags '(:expensive-test)
  (erc-scenarios-common-with-cleanup
      ((erc-scenarios-common-dialog "base/local-modules")
       (erc-server-flood-penalty 0.1)
       (dumb-server (erc-d-run "localhost" t 'first 'second 'fourth))
       (port (process-contact dumb-server :service))
       (erc-modules (cons 'sasl erc-modules))
       (expect (erc-d-t-make-expecter))
       (server-buffer-name (format "127.0.0.1:%d" port)))

    (ert-info ("Initial authentication succeeds as expected")
      (with-current-buffer (erc :server "127.0.0.1"
                                :port port
                                :nick "tester"
                                :user "tester"
                                :password "changeme"
                                :full-name "tester")
        (should (string= (buffer-name) server-buffer-name))
        (funcall expect 10 "You are now logged in as tester"))

      (with-current-buffer (erc-d-t-wait-for 10 (get-buffer "foonet"))
        (funcall expect 10 "This server is in debug mode")
        (erc-cmd-JOIN "#chan")

        (with-current-buffer (erc-d-t-wait-for 10 (get-buffer "#chan"))
          (funcall expect 20 "She is Lavinia, therefore must"))

        (erc-cmd-QUIT "")
        (funcall expect 10 "finished")))

    (ert-info ("Disabling works from a target buffer.")
      (with-current-buffer "#chan"
        (should erc-sasl-mode)
        (call-interactively #'erc-sasl-disable)
        (should-not erc-sasl-mode)
        (should (local-variable-p 'erc-sasl-mode))
        (should-not (buffer-local-value 'erc-sasl-mode (get-buffer "foonet")))
        (erc-cmd-RECONNECT)
        (with-current-buffer "#chan"
          (funcall expect 10 "Some enigma, some riddle")
          (should-not erc-sasl-mode) ; regression
          (should (local-variable-p 'erc-sasl-mode))))

      (with-current-buffer "foonet"
        (should (local-variable-p 'erc-sasl-mode))
        (funcall expect 10 "User modes for tester`")
        (erc-cmd-QUIT "")
        (funcall expect 10 "finished")))

    (ert-info ("Enabling works from a target buffer")
      (with-current-buffer "#chan"
        (call-interactively #'erc-sasl-enable)
        (should (local-variable-p 'erc-sasl-mode))
        (should erc-sasl-mode)
        (erc-cmd-RECONNECT)
        (funcall expect 10 "Well met; good morrow, Titus and Hortensius.")
        (erc-cmd-QUIT ""))

      (with-current-buffer "foonet"
        (should (local-variable-p 'erc-sasl-mode))
        (should erc-sasl-mode)
        (funcall expect 10 "User modes for tester")))))

;;; erc-scenarios-local-modules.el ends here
