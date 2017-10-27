'use strict';

var node = require('../../../node');
var shared = require('../../shared');
var constants = require('../../../../helpers/constants');

var sendTransactionPromise = require('../../../common/apiHelpers').sendTransactionPromise;
var creditAccountPromise = require('../../../common/apiHelpers').creditAccountPromise;
var waitForConfirmations = require('../../../common/apiHelpers').waitForConfirmations;

describe('POST /api/transactions (type 5) register dapp', function () {

	var transaction;
	var transactionsToWaitFor = [];
	var badTransactions = [];
	var goodTransactions = [];
	var badTransactionsEnforcement = [];
	var goodTransactionsEnforcement = [];

	var account = node.randomAccount();
	var accountNoFunds = node.randomAccount();
	var accountMinimalFunds = node.randomAccount();

	var dappDuplicate = node.randomApplication();
	var dappDuplicateNameSuccess = node.randomApplication();
	var dappDuplicateNameFail = node.randomApplication();
	dappDuplicateNameSuccess.name = dappDuplicateNameFail.name;
	var dappDuplicateLinkSuccess = node.randomApplication();
	var dappDuplicateLinkFail = node.randomApplication();
	dappDuplicateLinkSuccess.link = dappDuplicateLinkFail.link;

	// Crediting accounts
	before(function () {
		var promises = [];
		promises.push(creditAccountPromise(account.address, 1000 * node.normalizer));
		promises.push(creditAccountPromise(accountMinimalFunds.address, constants.fees.dappRegistration));

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

		shared.invalidAssets(account, 'dapp', badTransactions);

		describe('category', function () {
			
			it('without should fail', function () {
				transaction = node.lisk.dapp.createDapp(account.password, null, node.randomApplication());
				delete transaction.asset.dapp.category;

				return sendTransactionPromise(transaction).then(function (res) {
					node.expect(res).to.have.property('success').to.be.not.ok;
					node.expect(res).to.have.property('message').to.match(/Missing required property: category$/);
					badTransactions.push(transaction);
				});
			});

			it('with integer less than minimum should fail', function () {
				transaction = node.lisk.dapp.createDapp(account.password, null, node.randomApplication());
				transaction.asset.dapp.category = -1;

				return sendTransactionPromise(transaction).then(function (res) {
					node.expect(res).to.have.property('success').to.be.not.ok;
					node.expect(res).to.have.property('message').to.match(/Value -1 is less than minimum 0$/);
					badTransactions.push(transaction);
				});
			});

			it('with integer greater than maximum should fail', function () {
				transaction = node.lisk.dapp.createDapp(account.password, null, node.randomApplication());
				transaction.asset.dapp.category = 9;

				return sendTransactionPromise(transaction).then(function (res) {
					node.expect(res).to.have.property('success').to.be.not.ok;
					node.expect(res).to.have.property('message').to.match(/Value 9 is greater than maximum 8$/);
					badTransactions.push(transaction);
				});
			});
		});

		describe('description', function () {

			it('without should be ok', function () {
				var application = node.randomApplication();
				delete application.description;

				transaction = node.lisk.dapp.createDapp(account.password, null, application);

				return sendTransactionPromise(transaction).then(function (res) {
					node.expect(res).to.have.property('success').to.be.ok;
					node.expect(res).to.have.property('transactionId').to.equal(transaction.id);
					goodTransactions.push(transaction);
				});
			});

			it('with empty string should be ok', function () {
				var application = node.randomApplication();
				application.description = '';

				transaction = node.lisk.dapp.createDapp(account.password, null, application);

				return sendTransactionPromise(transaction).then(function (res) {
					node.expect(res).to.have.property('success').to.be.ok;
					node.expect(res).to.have.property('transactionId').to.equal(transaction.id);
					goodTransactions.push(transaction);
				});
			});

			it('with string longer than maximum(160) should fail', function () {
				var application = node.randomApplication();
				application.description = node.randomString.generate({
					length: 161
				});
				transaction = node.lisk.dapp.createDapp(account.password, null, application);

				return sendTransactionPromise(transaction).then(function (res) {
					node.expect(res).to.have.property('success').to.be.not.ok;
					node.expect(res).to.have.property('message').to.match(/String is too long \(161 chars\), maximum 160$/);
					badTransactions.push(transaction);
				});
			});
		});

		describe('icon', function () {

			it('without should be ok', function () {
				var application = node.randomApplication();
				delete application.icon;

				transaction = node.lisk.dapp.createDapp(account.password, null, application);

				return sendTransactionPromise(transaction).then(function (res) {
					node.expect(res).to.have.property('success').to.be.ok;
					node.expect(res).to.have.property('transactionId').to.equal(transaction.id);
					goodTransactions.push(transaction);
				});
			});

			it('with invalid url should fail', function () {
				var application = node.randomApplication();
				application.icon = 'invalidUrl';

				transaction = node.lisk.dapp.createDapp(account.password, null, application);

				return sendTransactionPromise(transaction).then(function (res) {
					node.expect(res).to.have.property('success').to.be.not.ok;
					node.expect(res).to.have.property('message').to.equal('Invalid application icon link');
					badTransactions.push(transaction);
				});
			});

			it('with invalid file type should fail', function () {
				var application = node.randomApplication();
				application.icon += '.invalid';

				transaction = node.lisk.dapp.createDapp(account.password, null, application);

				return sendTransactionPromise(transaction).then(function (res) {
					node.expect(res).to.have.property('success').to.be.not.ok;
					node.expect(res).to.have.property('message').to.equal('Invalid application icon file type');
					badTransactions.push(transaction);
				});
			});
		});

		describe('link', function () {
			
			it('with empty string should fail', function () {
				var application = node.randomApplication();
				application.link = '';

				transaction = node.lisk.dapp.createDapp(account.password, null, application);

				return sendTransactionPromise(transaction).then(function (res) {
					node.expect(res).to.have.property('success').to.be.not.ok;
					node.expect(res).to.have.property('message').to.equal('Invalid application link');
					badTransactions.push(transaction);
				});
			});

			it('with invalid extension type should fail', function () {
				var application = node.randomApplication();
				application.link += '.invalid';
				
				transaction = node.lisk.dapp.createDapp(account.password, null, application);

				return sendTransactionPromise(transaction).then(function (res) {
					node.expect(res).to.have.property('success').to.be.not.ok;
					node.expect(res).to.have.property('message').to.equal('Invalid application file type');
					badTransactions.push(transaction);
				});
			});
		});

		describe('name', function () {
			
			it('without should fail', function () {
				transaction = node.lisk.dapp.createDapp(account.password, null, node.randomApplication());
				delete transaction.asset.dapp.name;

				return sendTransactionPromise(transaction).then(function (res) {
					node.expect(res).to.have.property('success').to.be.not.ok;
					node.expect(res).to.have.property('message').to.match(/Missing required property: name$/);
					badTransactions.push(transaction);
				});
			});

			it('with empty string should fail', function () {
				transaction = node.lisk.dapp.createDapp(account.password, null, node.randomApplication());
				transaction.asset.dapp.name = '';

				return sendTransactionPromise(transaction).then(function (res) {
					node.expect(res).to.have.property('success').to.be.not.ok;
					node.expect(res).to.have.property('message').to.match(/String is too short \(0 chars\), minimum 1$/);
					badTransactions.push(transaction);
				});
			});

			it('with string longer than maximum(32) should fail', function () {
				var application = node.randomApplication();
				application.name = node.randomString.generate({
					length: 33
				});
				transaction = node.lisk.dapp.createDapp(account.password, null, application);

				return sendTransactionPromise(transaction).then(function (res) {
					node.expect(res).to.have.property('success').to.be.not.ok;
					node.expect(res).to.have.property('message').to.match(/String is too long \(33 chars\), maximum 32$/);
					badTransactions.push(transaction);
				});
			});
		});

		describe('tags', function () {

			it('without should be ok', function () {
				var application = node.randomApplication();
				delete application.tags;

				transaction = node.lisk.dapp.createDapp(account.password, null, application);

				return sendTransactionPromise(transaction).then(function (res) {
					node.expect(res).to.have.property('success').to.be.ok;
					node.expect(res).to.have.property('transactionId').to.equal(transaction.id);
					goodTransactions.push(transaction);
				});
			});

			it('with empty string should be ok', function () {
				var application = node.randomApplication();
				application.tags = '';

				transaction = node.lisk.dapp.createDapp(account.password, null, application);

				return sendTransactionPromise(transaction).then(function (res) {
					node.expect(res).to.have.property('success').to.be.ok;
					node.expect(res).to.have.property('transactionId').to.equal(transaction.id);
					goodTransactions.push(transaction);
				});
			});

			it('with string longer than maximum(160) should fail', function () {
				var application = node.randomApplication();
				application.tags = node.randomString.generate({
					length: 161
				});
				transaction = node.lisk.dapp.createDapp(account.password, null, application);

				return sendTransactionPromise(transaction).then(function (res) {
					node.expect(res).to.have.property('success').to.be.not.ok;
					node.expect(res).to.have.property('message').to.match(/String is too long \(161 chars\), maximum 160$/);
					badTransactions.push(transaction);
				});
			});

			it('with several should be ok', function () {
				var application = node.randomApplication();
				application.tags += ',' + node.randomApplicationName();

				transaction = node.lisk.dapp.createDapp(account.password, null, application);

				return sendTransactionPromise(transaction).then(function (res) {
					node.expect(res).to.have.property('success').to.be.ok;
					node.expect(res).to.have.property('transactionId').to.equal(transaction.id);
					goodTransactions.push(transaction);
				});
			});

			it('with duplicate tag should be ok', function () {
				var application = node.randomApplication();
				var tag = application.tags;
				application.tags += ',' + tag;

				transaction = node.lisk.dapp.createDapp(account.password, null, application);

				return sendTransactionPromise(transaction).then(function (res) {
					node.expect(res).to.have.property('success').to.be.not.ok;
					node.expect(res).to.have.property('message').to.equal('Encountered duplicate tag: ' + tag + ' in application');
					badTransactions.push(transaction);
				});
			});
		});

		describe('type', function () {
			
			it('without should fail', function () {
				transaction = node.lisk.dapp.createDapp(account.password, null, node.randomApplication());
				delete transaction.asset.dapp.type;

				return sendTransactionPromise(transaction).then(function (res) {
					node.expect(res).to.have.property('success').to.be.not.ok;
					node.expect(res).to.have.property('message').to.match(/Missing required property: type$/);
					badTransactions.push(transaction);
				});
			});

			it('with negative integer should fail', function () {
				transaction = node.lisk.dapp.createDapp(account.password, null, node.randomApplication());
				transaction.asset.dapp.type = -1;

				return sendTransactionPromise(transaction).then(function (res) {
					node.expect(res).to.have.property('success').to.be.not.ok;
					node.expect(res).to.have.property('message').to.match(/Value -1 is less than minimum 0$/);
					badTransactions.push(transaction);
				});
			});

			it('with integer smaller than minimum should fail', function () {
				transaction = node.lisk.dapp.createDapp(account.password, null, node.randomApplication());
				transaction.asset.dapp.type = -1;

				return sendTransactionPromise(transaction).then(function (res) {
					node.expect(res).to.have.property('success').to.be.not.ok;
					node.expect(res).to.have.property('message').to.match(/Value -1 is less than minimum 0$/);
					badTransactions.push(transaction);
				});
			});

			it('with integer greater than maximum should fail', function () {
				var application = node.randomApplication();
				application.type = 2;
				transaction = node.lisk.dapp.createDapp(account.password, null, application);

				return sendTransactionPromise(transaction).then(function (res) {
					node.expect(res).to.have.property('success').to.be.not.ok;
					node.expect(res).to.have.property('message').to.equal('Invalid application type');
					badTransactions.push(transaction);
				});
			});
		});
	});

	describe('transactions processing', function () {

		it('with no funds should fail', function () {
			transaction = node.lisk.dapp.createDapp(accountNoFunds.password, null, node.randomApplication());

			return sendTransactionPromise(transaction).then(function (res) {
				node.expect(res).to.have.property('success').to.not.be.ok;
				node.expect(res).to.have.property('message').to.equal('Account does not have enough LSK: ' + accountNoFunds.address + ' balance: 0');
				badTransactions.push(transaction);
			});
		});

		it('with minimal funds should be ok', function () {
			transaction = node.lisk.dapp.createDapp(accountMinimalFunds.password, null, node.randomApplication());

			return sendTransactionPromise(transaction).then(function (res) {
				node.expect(res).to.have.property('success').to.be.ok;
				node.expect(res).to.have.property('transactionId').to.equal(transaction.id);
				goodTransactions.push(transaction);
			});
		});

		it('with valid params should be ok', function () {
			transaction = node.lisk.dapp.createDapp(account.password, null, node.randomApplication());

			return sendTransactionPromise(transaction).then(function (res) {
				node.expect(res).to.have.property('success').to.be.ok;
				node.expect(res).to.have.property('transactionId').to.equal(transaction.id);
				goodTransactions.push(transaction);
			});
		});
	});

	describe('unconfirmed state', function () {
		
		it('duplicate submission identical app should be ok and only last transaction to arrive will be confirmed', function () {
			transaction = node.lisk.dapp.createDapp(account.password, null, dappDuplicate);

			return sendTransactionPromise(transaction)
				.then(function (res) {
					node.expect(res).to.have.property('success').to.be.ok;
					node.expect(res).to.have.property('transactionId').to.equal(transaction.id);
					badTransactions.push(transaction);
				})
				.then(function (res) {
					// Transaction with same info but different ID (due to timeOffSet parameter)
					transaction = node.lisk.dapp.createDapp(account.password, null, dappDuplicate, 1);

					return sendTransactionPromise(transaction);
				})
				.then(function (res) {
					node.expect(res).to.have.property('success').to.be.ok;
					node.expect(res).to.have.property('transactionId').to.equal(transaction.id);
					goodTransactions.push(transaction);
				});
		});

		it('two different dapps with same name should be ok and only last transaction to arrive will be confirmed', function () {
			transaction = node.lisk.dapp.createDapp(account.password, null, dappDuplicateNameFail);

			return sendTransactionPromise(transaction)
				.then(function (res) {
					node.expect(res).to.have.property('success').to.be.ok;
					node.expect(res).to.have.property('transactionId').to.equal(transaction.id);
					badTransactions.push(transaction);
				})
				.then(function (res) {
					// Transaction with same info but different ID (due to timeOffSet parameter)
					transaction = node.lisk.dapp.createDapp(account.password, null, dappDuplicateNameSuccess);

					return sendTransactionPromise(transaction);
				})
				.then(function (res) {
					node.expect(res).to.have.property('success').to.be.ok;
					node.expect(res).to.have.property('transactionId').to.equal(transaction.id);
					goodTransactions.push(transaction);
				});
		});

		it('two different dapps with same link should be ok and only last transaction to arrive will be confirmed', function () {
			transaction = node.lisk.dapp.createDapp(account.password, null, dappDuplicateLinkFail);

			return sendTransactionPromise(transaction)
				.then(function (res) {
					node.expect(res).to.have.property('success').to.be.ok;
					node.expect(res).to.have.property('transactionId').to.equal(transaction.id);
					badTransactions.push(transaction);
				})
				.then(function (res) {
					// Transaction with same info but different ID (due to timeOffSet parameter)
					transaction = node.lisk.dapp.createDapp(account.password, null, dappDuplicateLinkSuccess);

					return sendTransactionPromise(transaction);
				})
				.then(function (res) {
					node.expect(res).to.have.property('success').to.be.ok;
					node.expect(res).to.have.property('transactionId').to.equal(transaction.id);
					goodTransactions.push(transaction);
				});
		});	
	});
	
	describe('confirmation', function () {

		shared.confirmationPhase(goodTransactions, badTransactions);
	});

	describe('validation', function () {

		it('using registered name shoudl fail', function () {
			transaction = node.lisk.dapp.createDapp(account.password, null, dappDuplicateNameFail);

			return sendTransactionPromise(transaction).then(function (res) {
				node.expect(res).to.have.property('success').to.be.not.ok;
				node.expect(res).to.have.property('message').to.equal('Application name already exists: ' + dappDuplicateNameFail.name);
				badTransactionsEnforcement.push(transaction);
			});
		});

		it('using registered link shoudl fail', function () {
			transaction = node.lisk.dapp.createDapp(account.password, null, dappDuplicateLinkFail);

			return sendTransactionPromise(transaction).then(function (res) {
				node.expect(res).to.have.property('success').to.be.not.ok;
				node.expect(res).to.have.property('message').to.equal('Application link already exists: ' + dappDuplicateLinkFail.link);
				badTransactionsEnforcement.push(transaction);
			});
		});	
	});

	describe('confirm validation', function () {

		shared.confirmationPhase(goodTransactionsEnforcement, badTransactionsEnforcement);
	});
});