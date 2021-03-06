'use strict';

var node = require('../../../node');
var shared = require('../../shared');
var constants = require('../../../../helpers/constants');

var sendTransactionPromise = require('../../../common/apiHelpers').sendTransactionPromise;
var creditAccountPromise = require('../../../common/apiHelpers').creditAccountPromise;
var sendSignaturePromise = require('../../../common/apiHelpers').sendSignaturePromise;
var waitForConfirmations = require('../../../common/apiHelpers').waitForConfirmations;

describe('POST /api/transactions (type 1) register second secret', function () {

	var transaction, signature;
	var transactionsToWaitFor = [];
	var badTransactions = [];
	var goodTransactions = [];
	var badTransactionsEnforcement = [];
	var goodTransactionsEnforcement = [];
	var pendingMultisignatures = [];

	var account = node.randomAccount();
	var accountNoFunds = node.randomAccount();
	var accountMinimalFunds = node.randomAccount();
	var accountNoSecondPassword = node.randomAccount();
	var accountDuplicate = node.randomAccount();

	// Crediting accounts
	before(function () {
		var promises = [];
		promises.push(creditAccountPromise(account.address, 1000 * node.normalizer));
		promises.push(creditAccountPromise(accountMinimalFunds.address, constants.fees.secondSignature));
		promises.push(creditAccountPromise(accountNoSecondPassword.address, constants.fees.secondSignature));
		promises.push(creditAccountPromise(accountDuplicate.address, constants.fees.secondSignature));

		return node.Promise.all(promises)
			.then(function (results) {
				results.forEach(function (res) {
					node.expect(res).to.have.property('success').to.be.ok;
					node.expect(res).to.have.property('transactionId').that.is.not.empty;
					transactionsToWaitFor.push(res.transactionId);
				});
			})
			.then(function (res) {
				return waitForConfirmations(transactionsToWaitFor);
			});
	});

	describe('schema validations', function () {

		shared.invalidAssets(account, 'signature', badTransactions);
	});

	describe('transactions processing', function () {

		it('using second passphrase on a fresh account should fail', function () {
			transaction = node.lisk.transaction.createTransaction(node.eAccount.address, 1, accountNoSecondPassword.password, accountNoSecondPassword.secondPassword);

			return sendTransactionPromise(transaction).then(function (res) {
				node.expect(res).to.have.property('success').to.be.not.ok;
				node.expect(res).to.have.property('message').to.equal('Sender does not have a second signature');
				badTransactionsEnforcement.push(transaction);
			});
		});

		it('with no funds should fail', function () {
			transaction = node.lisk.signature.createSignature(accountNoFunds.password, accountNoFunds.secondPassword);

			return sendTransactionPromise(transaction).then(function (res) {
				node.expect(res).to.have.property('success').to.not.be.ok;
				node.expect(res).to.have.property('message').to.equal('Account does not have enough LSK: ' + accountNoFunds.address + ' balance: 0');
				badTransactions.push(transaction);
			});
		});

		it('with minimal required amount of funds should be ok', function () {
			transaction = node.lisk.signature.createSignature(accountMinimalFunds.password, accountMinimalFunds.secondPassword);

			return sendTransactionPromise(transaction).then(function (res) {
				node.expect(res).to.have.property('success').to.be.ok;
				node.expect(res).to.have.property('transactionId').to.equal(transaction.id);
				goodTransactions.push(transaction);
			});
		});

		it('with valid params should be ok', function () {
			transaction = node.lisk.signature.createSignature(account.password, account.secondPassword, 1);

			return sendTransactionPromise(transaction).then(function (res) {
				node.expect(res).to.have.property('success').to.be.ok;
				node.expect(res).to.have.property('transactionId').to.equal(transaction.id);
				goodTransactions.push(transaction);
			});
		});
	});

	describe('unconfirmed state', function () {

		describe('type 0 - sending funds', function () {

			it('using second signature with an account that has a pending second passphrase registration should fail', function () {
				transaction = node.lisk.transaction.createTransaction(node.eAccount.address, 1, account.password, account.secondPassword);

				return sendTransactionPromise(transaction).then(function (res) {
					node.expect(res).to.have.property('success').to.be.not.ok;
					node.expect(res).to.have.property('message').to.equal('Sender does not have a second signature');
					badTransactions.push(transaction);
				});
			});
		});

		describe('type 1 - second secret', function () {

			it('with valid params and duplicate submission should be ok but just last transaction will be confirmed', function () {
				transaction = node.lisk.signature.createSignature(accountDuplicate.password, 'secondpassword');

				return sendTransactionPromise(transaction).then(function (res) {
					node.expect(res).to.have.property('success').to.be.ok;
					node.expect(res).to.have.property('transactionId').to.equal(transaction.id);
					badTransactions.push(transaction);

					transaction = node.lisk.signature.createSignature(accountDuplicate.password, accountDuplicate.secondPassword);

					return sendTransactionPromise(transaction).then(function (res) {
						node.expect(res).to.have.property('success').to.be.ok;
						node.expect(res).to.have.property('transactionId').to.equal(transaction.id);
						goodTransactions.push(transaction);
					});
				});
			});
		});

		describe('type 2 - registering delegate', function () {

			it('using second signature with an account that has a pending second passphrase registration should fail', function () {
				transaction = node.lisk.delegate.createDelegate(account.password, account.username, account.secondPassword);

				return sendTransactionPromise(transaction).then(function (res) {
					node.expect(res).to.have.property('success').to.be.not.ok;
					node.expect(res).to.have.property('message').to.equal('Sender does not have a second signature');
					badTransactions.push(transaction);
				});
			});
		});

		describe('type 3 - voting delegate', function () {

			it('using second signature with an account that has a pending second passphrase registration should fail', function () {
				transaction = node.lisk.vote.createVote(account.password, ['+' + node.eAccount.publicKey], account.secondPassword);

				return sendTransactionPromise(transaction).then(function (res) {
					node.expect(res).to.have.property('success').to.be.not.ok;
					node.expect(res).to.have.property('message').to.equal('Sender does not have a second signature');
					badTransactions.push(transaction);
				});
			});
		});

		describe('type 4 - registering multisignature account', function () {

			it('using second signature with an account that has a pending second passphrase registration should fail', function () {
				transaction = node.lisk.multisignature.createMultisignature(account.password, account.secondPassword, ['+' + node.eAccount.publicKey, '+' + accountNoFunds.publicKey], 1, 2);

				return sendTransactionPromise(transaction).then(function (res) {
					node.expect(res).to.have.property('success').to.be.not.ok;
					node.expect(res).to.have.property('message').to.equal('Sender does not have a second signature');
					badTransactions.push(transaction);
				});
			});
		});

		describe('type 5 - registering dapp', function () {

			it('using second signature with an account that has a pending second passphrase registration should fail', function () {
				transaction = node.lisk.dapp.createDapp(account.password, account.secondPassword, node.randomApplication());

				return sendTransactionPromise(transaction).then(function (res) {
					node.expect(res).to.have.property('success').to.be.not.ok;
					node.expect(res).to.have.property('message').to.equal('Sender does not have a second signature');
					badTransactions.push(transaction);
				});
			});
		});
	});	

	describe('confirmation', function () {

		shared.confirmationPhase(goodTransactions, badTransactions);
	});

	describe('validation', function () {

		describe('type 0 - sending funds', function () {

			it('using no second passphrase on an account with second passphrase enabled should fail', function () {
				transaction = node.lisk.transaction.createTransaction(node.eAccount.address, 1, account.password);

				return sendTransactionPromise(transaction).then(function (res) {
					node.expect(res).to.have.property('success').to.be.not.ok;
					node.expect(res).to.have.property('message').to.equal('Missing sender second signature');
					badTransactionsEnforcement.push(transaction);
				});
			});

			it('using second passphrase not matching registered secondPublicKey should fail', function () {
				transaction = node.lisk.transaction.createTransaction(node.eAccount.address, 1, account.password, 'invalid password');

				return sendTransactionPromise(transaction).then(function (res) {
					node.expect(res).to.have.property('success').to.be.not.ok;
					node.expect(res).to.have.property('message').to.equal('Failed to verify second signature');
					badTransactionsEnforcement.push(transaction);
				});
			});

			it('using correct second passphrase should be ok', function () {
				transaction = node.lisk.transaction.createTransaction(node.eAccount.address, 1, account.password, account.secondPassword);

				return sendTransactionPromise(transaction).then(function (res) {
					node.expect(res).to.have.property('success').to.be.ok;
					node.expect(res).to.have.property('transactionId').to.equal(transaction.id);
					goodTransactionsEnforcement.push(transaction);
				});
			});
		});

		describe('type 1 - second secret', function () {

			it('registering a second passphrase on an account with a second passphrase already enabled should fail', function () {
				transaction = node.lisk.signature.createSignature(account.password, node.randomPassword());
				var secondKeys = node.lisk.crypto.getKeys(account.secondPassword);
				node.lisk.crypto.secondSign(transaction, secondKeys);
				transaction.id = node.lisk.crypto.getId(transaction);

				return sendTransactionPromise(transaction).then(function (res) {
					node.expect(res).to.have.property('success').to.not.be.ok;
					node.expect(res).to.have.property('message').to.equal('Missing sender second signature');
					badTransactionsEnforcement.push(transaction);
				});
			});
		});

		describe('type 2 - registering delegate', function () {

			it('using no second passphrase on an account with second passphrase enabled should fail', function () {
				transaction = node.lisk.delegate.createDelegate(account.password, account.username);

				return sendTransactionPromise(transaction).then(function (res) {
					node.expect(res).to.have.property('success').to.be.not.ok;
					node.expect(res).to.have.property('message').to.equal('Missing sender second signature');
					badTransactionsEnforcement.push(transaction);
				});
			});

			it('using second passphrase not matching registered secondPublicKey should fail', function () {
				transaction = node.lisk.delegate.createDelegate(account.password, account.username, 'invalid password');

				return sendTransactionPromise(transaction).then(function (res) {
					node.expect(res).to.have.property('success').to.be.not.ok;
					node.expect(res).to.have.property('message').to.equal('Failed to verify second signature');
					badTransactionsEnforcement.push(transaction);
				});
			});

			it('using correct second passphrase should be ok', function () {
				transaction = node.lisk.delegate.createDelegate(account.password, account.username, account.secondPassword);

				return sendTransactionPromise(transaction).then(function (res) {
					node.expect(res).to.have.property('success').to.be.ok;
					node.expect(res).to.have.property('transactionId').to.equal(transaction.id);
					goodTransactionsEnforcement.push(transaction);
				});
			});
		});

		describe('type 3 - voting delegate', function () {

			it('using no second passphrase on an account with second passphrase enabled should fail', function () {
				transaction = node.lisk.vote.createVote(account.password, ['+' + node.eAccount.publicKey]);

				return sendTransactionPromise(transaction).then(function (res) {
					node.expect(res).to.have.property('success').to.be.not.ok;
					node.expect(res).to.have.property('message').to.equal('Missing sender second signature');
					badTransactionsEnforcement.push(transaction);
				});
			});

			it('using second passphrase not matching registered secondPublicKey should fail', function () {
				transaction = node.lisk.vote.createVote(account.password, ['+' + node.eAccount.publicKey], 'invalid password');

				return sendTransactionPromise(transaction).then(function (res) {
					node.expect(res).to.have.property('success').to.be.not.ok;
					node.expect(res).to.have.property('message').to.equal('Failed to verify second signature');
					badTransactionsEnforcement.push(transaction);
				});
			});

			it('using correct second passphrase should be ok', function () {
				transaction = node.lisk.vote.createVote(account.password, ['+' + node.eAccount.publicKey], account.secondPassword);

				return sendTransactionPromise(transaction).then(function (res) {
					node.expect(res).to.have.property('success').to.be.ok;
					node.expect(res).to.have.property('transactionId').to.equal(transaction.id);
					goodTransactionsEnforcement.push(transaction);
				});
			});
		});

		describe('type 4 - registering multisignature account', function () {

			it('using no second passphrase on an account with second passphrase enabled should fail', function () {
				transaction = node.lisk.multisignature.createMultisignature(account.password, null, ['+' + node.eAccount.publicKey, '+' + accountNoFunds.publicKey, '+' + accountMinimalFunds.publicKey], 1, 2);

				return sendTransactionPromise(transaction).then(function (res) {
					node.expect(res).to.have.property('success').to.be.not.ok;
					node.expect(res).to.have.property('message').to.equal('Missing sender second signature');
					badTransactionsEnforcement.push(transaction);
				});
			});

			it('using second passphrase not matching registered secondPublicKey should fail', function () {
				transaction = node.lisk.multisignature.createMultisignature(account.password, 'wrong second password', ['+' + node.eAccount.publicKey, '+' + accountNoFunds.publicKey, '+' + accountMinimalFunds.publicKey], 1, 2);

				return sendTransactionPromise(transaction).then(function (res) {
					node.expect(res).to.have.property('success').to.be.not.ok;
					node.expect(res).to.have.property('message').to.equal('Failed to verify second signature');
					badTransactionsEnforcement.push(transaction);
				});
			});

			it('using correct second passphrase should be ok', function () {
				transaction = node.lisk.multisignature.createMultisignature(account.password, account.secondPassword, ['+' + node.eAccount.publicKey, '+' + accountNoFunds.publicKey], 1, 2);

				return sendTransactionPromise(transaction).then(function (res) {
					node.expect(res).to.have.property('success').to.be.ok;
					node.expect(res).to.have.property('transactionId').to.equal(transaction.id);
					pendingMultisignatures.push(transaction);
				});
			});

			describe('signing transactions', function () {

				it('with not all the signatures should be ok but never confirmed', function () {
					signature = node.lisk.multisignature.signTransaction(pendingMultisignatures[0], accountNoFunds.password);

					return sendSignaturePromise(signature, pendingMultisignatures[0]).then(function (res) {
						node.expect(res).to.have.property('success').to.be.ok;
					});
				});
			});
		});

		describe('type 5 - registering dapp', function () {

			it('using no second passphrase on an account with second passphrase enabled should fail', function () {
				transaction = node.lisk.dapp.createDapp(account.password, null, node.randomApplication());

				return sendTransactionPromise(transaction).then(function (res) {
					node.expect(res).to.have.property('success').to.be.not.ok;
					node.expect(res).to.have.property('message').to.equal('Missing sender second signature');
					badTransactionsEnforcement.push(transaction);
				});
			});

			it('using second passphrase not matching registered secondPublicKey should fail', function () {
				transaction = node.lisk.dapp.createDapp(account.password, 'wrong second password', node.randomApplication());

				return sendTransactionPromise(transaction).then(function (res) {
					node.expect(res).to.have.property('success').to.be.not.ok;
					node.expect(res).to.have.property('message').to.equal('Failed to verify second signature');
					badTransactionsEnforcement.push(transaction);
				});
			});

			it('using correct second passphrase should be ok', function () {
				transaction = node.lisk.dapp.createDapp(account.password, account.secondPassword, node.randomApplication());

				return sendTransactionPromise(transaction).then(function (res) {
					node.expect(res).to.have.property('success').to.be.ok;
					node.expect(res).to.have.property('transactionId').to.equal(transaction.id);
					goodTransactionsEnforcement.push(transaction);
				});
			});
		});
	});

	describe('confirm validation', function () {

		shared.confirmationPhase(goodTransactionsEnforcement, badTransactionsEnforcement, pendingMultisignatures);
	});
});
